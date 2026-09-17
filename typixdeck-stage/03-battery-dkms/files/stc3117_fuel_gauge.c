// SPDX-License-Identifier: GPL-2.0
/*
 * stc3117_fuel_gauge.c - STMicroelectronics STC3117 Fuel Gauge Driver
 *
 * TypixDeck out-of-tree build of the mainline v6.18 driver with fixes
 * (see README.md, section "驱动补丁"):
 *  - OCV table is 16 points x 16 bit at 0x30..0x4F (mainline wrote 16 bytes)
 *  - SOC table lives at 0x50, not 0x30
 *  - CAPACITY reported in percent (mainline exported tenths of percent)
 *  - REG_CURRENT / REG_AVG_CURRENT are signed 14-bit (mainline read unsigned)
 *  - Linux ABI sign: positive current = charging
 *  - do not reconfigure/reset a gauge that is already running unless the
 *    chip reports BATFAIL/PORDET ("read-only takeover", another MCU may own it)
 *  - battery internal resistance from factory-internal-resistance-micro-ohms
 *
 * Copyright (c) 2024 Silicon Signals Pvt Ltd.
 * Author:      Hardevsinh Palaniya <hardevsinh.palaniya@siliconsignals.io>
 *              Bhavin Sharma <bhavin.sharma@siliconsignals.io>
 */

#include <linux/crc8.h>
#include <linux/devm-helpers.h>
#include <linux/i2c.h>
#include <linux/power_supply.h>
#include <linux/regmap.h>
#include <linux/workqueue.h>

#define STC3117_ADDR_MODE                      0x00
#define STC3117_ADDR_CTRL                      0x01
#define STC3117_ADDR_SOC_L                     0x02
#define STC3117_ADDR_SOC_H                     0x03
#define STC3117_ADDR_COUNTER_L                 0x04
#define STC3117_ADDR_COUNTER_H                 0x05
#define STC3117_ADDR_CURRENT_L                 0x06
#define STC3117_ADDR_CURRENT_H                 0x07
#define STC3117_ADDR_VOLTAGE_L                 0x08
#define STC3117_ADDR_VOLTAGE_H                 0x09
#define STC3117_ADDR_TEMPERATURE               0x0A
#define STC3117_ADDR_AVG_CURRENT_L             0x0B
#define STC3117_ADDR_AVG_CURRENT_H             0x0C
#define STC3117_ADDR_OCV_L                     0x0D
#define STC3117_ADDR_OCV_H                     0x0E
#define STC3117_ADDR_CC_CNF_L                  0x0F
#define STC3117_ADDR_CC_CNF_H                  0x10
#define STC3117_ADDR_VM_CNF_L                  0x11
#define STC3117_ADDR_VM_CNF_H                  0x12
#define STC3117_ADDR_ALARM_soc                 0x13
#define STC3117_ADDR_ALARM_VOLTAGE             0x14
#define STC3117_ADDR_ID                        0x18
#define STC3117_ADDR_CC_ADJ_L			0x1B
#define STC3117_ADDR_CC_ADJ_H			0x1C
#define STC3117_ADDR_VM_ADJ_L			0x1D
#define STC3117_ADDR_VM_ADJ_H			0x1E
#define STC3117_ADDR_RAM			0x20
#define STC3117_ADDR_OCV_TABLE			0x30
#define STC3117_ADDR_SOC_TABLE			0x50

/* Bit mask definition */
#define STC3117_ID			        0x16
#define STC3117_MIXED_MODE			0x00
#define STC3117_VMODE				BIT(0)
#define STC3117_GG_RUN				BIT(4)
#define STC3117_CC_MODE			BIT(5)
#define STC3117_BATFAIL			BIT(3)
#define STC3117_PORDET				BIT(4)
#define STC3117_RAM_SIZE			16
#define STC3117_OCV_TABLE_SIZE			16
#define STC3117_RAM_TESTWORD			0x53A9
#define STC3117_SOFT_RESET                     0x11
#define STC3117_NOMINAL_CAPACITY		2600

#define VOLTAGE_LSB_VALUE			9011
#define CURRENT_LSB_VALUE			24084
#define APP_CUTOFF_VOLTAGE			2500
#define MAX_HRSOC				51200
#define MAX_SOC				1000
#define CHG_MIN_CURRENT			200
#define CHG_END_CURRENT			20
#define APP_MIN_CURRENT			(-5)
#define BATTERY_FULL				95
/*
 * Re-seed the gauge when the OCV it derives from its own SOC and the OCV
 * measured at the terminals disagree by more than this. Comparing voltages
 * rather than percentages is deliberate: along the flat part of a Li-ion
 * curve a large SOC error is worth only a few mV, and there the coulomb
 * counter is the better estimate anyway - so this never fires where
 * re-seeding could not help.
 */
#define STC3117_RESEED_OCV_DELTA_UV		120000
/*
 * ... and only after that many consecutive steady samples. REG_VOLTAGE and
 * REG_CURRENT are converted in separate cycles, so across a load step the two
 * do not belong together and the IR-corrected OCV can be hundreds of mV out.
 * On a deck whose USB input was dropping in and out, one such mismatched pair
 * (3803 mV paired with +691 mA while the pack was in fact sagging under a
 * 1.4 A discharge) was enough to throw an 83 % gauge down to 39 %.
 */
#define STC3117_SEED_VOTES			5	/* ~10 s at the 2 s poll */
#define STC3117_SEED_STEADY_UA			200000
/* RAM byte 10: set once this driver has seeded the gauge for this battery */
#define STC3117_SEED_MARK			0x5D
#define CRC8_POLYNOMIAL			0x07
#define CRC8_INIT				0x00

DECLARE_CRC8_TABLE(stc3117_crc_table);

enum stc3117_state {
	STC3117_INIT,
	STC3117_RUNNING,
	STC3117_POWERDN,
};

/*
 * Rest OCV curve of the 604070 4.2 V LiCoO2 pack, in mV, against the SOC
 * breakpoints below. Two things mainline gets wrong for this board:
 *
 *  - its curve ends at 4320 mV, which belongs to a 4.35 V cell. Fed a 4.2 V
 *    pack it tops out near 91 % and the deck never shows a full battery.
 *  - it pairs the 16 points with an even 0/6.67/13.3/... split, while it is
 *    the SOC table that decides the pairing. REG_SOCTAB is left at ST's
 *    default (0/3/6/10/15/.../90/100 %, verified by dumping 0x50-0x5F on a
 *    0720 board), so the even split silently shifts the whole curve.
 *
 * Both tables are written together now, so the pairing no longer depends on
 * whatever the other MCU behind the mux left in the chip.
 */
static const int ocv_value[16] = {
	3300, 3450, 3568, 3640, 3680, 3700, 3730, 3750,
	3790, 3820, 3870, 3900, 3940, 4020, 4100, 4200
};

/* REG_SOCTAB0..15, 0.5 % per LSB: 0, 3, 6, 10, 15 ... 90, 100 % */
static const u8 soc_value[16] = {
	0x00, 0x06, 0x0c, 0x14, 0x1e, 0x28, 0x32, 0x3c,
	0x50, 0x64, 0x78, 0x82, 0x8c, 0xa0, 0xb4, 0xc8
};

/*
 * OCV in uV that the curve assigns to a SOC in tenths of a percent - the
 * inverse of what the gauge does, used to tell a believable gauge state from
 * an impossible one.
 */
static int stc3117_ocv_from_soc(int soc10)
{
	int i;

	soc10 = clamp(soc10, 0, MAX_SOC);
	for (i = 1; i < STC3117_OCV_TABLE_SIZE; i++) {
		int lo = soc_value[i - 1] * 5;	/* 0.5 % units -> tenths */
		int hi = soc_value[i] * 5;

		if (soc10 <= hi)
			return (ocv_value[i - 1] +
				(ocv_value[i] - ocv_value[i - 1]) *
				(soc10 - lo) / (hi - lo)) * 1000;
	}
	return ocv_value[STC3117_OCV_TABLE_SIZE - 1] * 1000;
}

union stc3117_internal_ram {
	u8 ram_bytes[STC3117_RAM_SIZE];
	struct {
	u16 testword;   /* 0-1    Bytes */
	u16 hrsoc;      /* 2-3    Bytes */
	u16 cc_cnf;     /* 4-5    Bytes */
	u16 vm_cnf;     /* 6-7    Bytes */
	u8 soc;         /* 8      Byte  */
	u8 state;       /* 9      Byte  */
	u8 seed_mark;   /* 10     Byte  */
	u8 unused[4];   /* 11-14  Bytes */
	u8 crc;         /* 15     Byte  */
	} reg;
};

struct stc3117_battery_info {
	int voltage_min_mv;
	int voltage_max_mv;
	int battery_capacity_mah;
	int sense_resistor;
};

struct stc3117_data {
	struct i2c_client *client;
	struct regmap *regmap;
	struct delayed_work update_work;
	struct power_supply *battery;
	union stc3117_internal_ram ram_data;
	struct stc3117_battery_info battery_info;

	int cc_cnf;
	int vm_cnf;
	int rint_mohm;		/* battery internal resistance, default 200 */
	bool takeover;		/* gauge was already running at probe: never reset it */
	bool need_seed;		/* gauge carries no seed mark for this battery */
	int seed_votes;		/* consecutive steady samples asking for a seed */
	int seed_prev_current;	/* battery current at the previous vote */
	bool inited;		/* stc3117_init() succeeded (chip reachable) */
	int cc_adj;
	int vm_adj;
	int avg_current;
	int avg_voltage;
	int batt_current;
	int voltage;
	int temp;
	int soc;
	int ocv;
	int hrsoc;
	int presence;
};

/* REG_CURRENT / REG_AVG_CURRENT are 14-bit two's complement */
static int stc3117_sext14(int value)
{
	value &= 0x3FFF;
	return value >= 0x2000 ? value - 0x4000 : value;
}

static int stc3117_convert(int value, int factor)
{
	value = (value * factor) / 4096;
	return value * 1000;
}

static int stc3117_get_battery_data(struct stc3117_data *data)
{
	u8 reg_list[16];
	u8 data_adjust[4];
	int value, mode;

	regmap_bulk_read(data->regmap, STC3117_ADDR_MODE,
			 reg_list, sizeof(reg_list));

	/* soc */
	value = (reg_list[3] << 8) + reg_list[2];
	data->hrsoc = value;
	data->soc = (value * 10 + 256) / 512;

	/* current in uA (signed 14-bit, positive = charging per Linux ABI) */
	value = stc3117_sext14((reg_list[7] << 8) + reg_list[6]);
	data->batt_current = stc3117_convert(value,
			CURRENT_LSB_VALUE / data->battery_info.sense_resistor);

	/* voltage in uV */
	value = (reg_list[9] << 8) + reg_list[8];
	data->voltage = stc3117_convert(value, VOLTAGE_LSB_VALUE);

	/* temp in 1/10 °C */
	data->temp = reg_list[10] * 10;

	/* Avg current in uA */
	value = stc3117_sext14((reg_list[12] << 8) + reg_list[11]);
	regmap_read(data->regmap, STC3117_ADDR_MODE, &mode);
	if (!(mode & STC3117_VMODE)) {
		value = stc3117_convert(value,
			CURRENT_LSB_VALUE / data->battery_info.sense_resistor);
		value = value / 4;
	} else {
		value = stc3117_convert(value, 36 * STC3117_NOMINAL_CAPACITY);
	}
	data->avg_current = value;

	/* ocv in uV */
	value = (reg_list[14] << 8) + reg_list[13];
	value = stc3117_convert(value, VOLTAGE_LSB_VALUE);
	value = (value + 2) / 4;
	data->ocv = value;

	/* CC & VM adjustment counters */
	regmap_bulk_read(data->regmap, STC3117_ADDR_CC_ADJ_L,
			 data_adjust, sizeof(data_adjust));
	value = (data_adjust[1] << 8) + data_adjust[0];
	data->cc_adj = value;

	value = (data_adjust[3] << 8) + data_adjust[2];
	data->vm_adj = value;

	return 0;
}

static int ram_write(struct stc3117_data *data)
{
	int ret;

	ret = regmap_bulk_write(data->regmap, STC3117_ADDR_RAM,
				data->ram_data.ram_bytes, STC3117_RAM_SIZE);
	if (ret)
		return ret;

	return 0;
};

static int ram_read(struct stc3117_data *data)
{
	int ret;

	ret = regmap_bulk_read(data->regmap, STC3117_ADDR_RAM,
			       data->ram_data.ram_bytes, STC3117_RAM_SIZE);
	if (ret)
		return ret;

	return 0;
};

static int stc3117_set_para(struct stc3117_data *data)
{
	int ret;

	ret = regmap_write(data->regmap, STC3117_ADDR_MODE, STC3117_VMODE);

	{
		/* REG_OCVTAB0..15: 2 bytes per point (LSB first), 0.55 mV/LSB */
		u8 ocv_regs[STC3117_OCV_TABLE_SIZE * 2];

		for (int i = 0; i < STC3117_OCV_TABLE_SIZE; i++) {
			int code = ocv_value[i] * 100 / 55;

			ocv_regs[2 * i] = code & 0xFF;
			ocv_regs[2 * i + 1] = (code >> 8) & 0xFF;
		}
		ret |= regmap_bulk_write(data->regmap, STC3117_ADDR_OCV_TABLE,
					 ocv_regs, sizeof(ocv_regs));
	}
	ret |= regmap_bulk_write(data->regmap, STC3117_ADDR_SOC_TABLE,
				 soc_value, sizeof(soc_value));

	ret |= regmap_write(data->regmap, STC3117_ADDR_CC_CNF_H,
				(data->ram_data.reg.cc_cnf >> 8) & 0xFF);

	ret |= regmap_write(data->regmap, STC3117_ADDR_CC_CNF_L,
					data->ram_data.reg.cc_cnf & 0xFF);

	ret |= regmap_write(data->regmap, STC3117_ADDR_VM_CNF_H,
				(data->ram_data.reg.vm_cnf >> 8) & 0xFF);

	ret |= regmap_write(data->regmap, STC3117_ADDR_VM_CNF_L,
					data->ram_data.reg.vm_cnf & 0xFF);

	ret |= regmap_write(data->regmap, STC3117_ADDR_CTRL, 0x03);

	ret |= regmap_write(data->regmap, STC3117_ADDR_MODE,
					STC3117_MIXED_MODE | STC3117_GG_RUN);

	return ret;
};

/*
 * Restart the gauge from a measured open-circuit voltage: reload the curve and
 * the configuration, GG_RST, then hand it REG_OCV so it looks the SOC up in
 * the table it has just been given.
 */
static int stc3117_seed(struct stc3117_data *data, int ocv_uv)
{
	int code = ocv_uv / 550;	/* REG_OCV: 0.55 mV/LSB */
	int ret;

	data->ram_data.reg.testword = STC3117_RAM_TESTWORD;
	data->ram_data.reg.cc_cnf = data->cc_cnf;
	data->ram_data.reg.vm_cnf = data->vm_cnf;
	data->ram_data.reg.seed_mark = STC3117_SEED_MARK;

	ret = stc3117_set_para(data);
	ret |= regmap_write(data->regmap, STC3117_ADDR_OCV_H, (code >> 8) & 0xFF);
	ret |= regmap_write(data->regmap, STC3117_ADDR_OCV_L, code & 0xFF);

	/* GG_RST restarted the conversions: wait them out before trusting reads */
	data->ram_data.reg.state = STC3117_INIT;
	return ret;
}

/*
 * Decide, one sample at a time, whether the gauge's SOC can be true. A sample
 * only counts when the current has barely moved since the last one, because
 * voltage and current come from different conversion cycles; and it takes
 * STC3117_SEED_VOTES of them in a row to act, so no transient can reseed a
 * healthy gauge. Call with fresh readings and after ram_read().
 */
static void stc3117_seed_check(struct stc3117_data *data)
{
	int ir_drop_uv, ocv_uv, curve_uv, slack_uv;
	bool steady, impossible;

	if (data->voltage <= 0 || data->soc < 0)
		return;

	steady = abs(data->batt_current - data->seed_prev_current) <
		 STC3117_SEED_STEADY_UA;
	data->seed_prev_current = data->batt_current;
	if (!steady) {
		data->seed_votes = 0;
		return;
	}

	/* uA * mOhm / 1000 = uV; positive current (charging) raises V */
	ir_drop_uv = data->batt_current / 1000 * data->rint_mohm;
	ocv_uv = clamp(data->voltage - ir_drop_uv, 3000000, 4300000);
	curve_uv = stc3117_ocv_from_soc(data->soc);
	/*
	 * Rint is a measured but still nominal number, so the IR correction is
	 * only good to roughly +-50 %: widen the tolerance with the load, or
	 * charging at 1 A reads as a wrong SOC.
	 */
	slack_uv = STC3117_RESEED_OCV_DELTA_UV + abs(ir_drop_uv) / 2;
	impossible = abs(ocv_uv - curve_uv) > slack_uv;

	if (!data->need_seed && !impossible) {
		data->seed_votes = 0;
		return;
	}
	if (++data->seed_votes < STC3117_SEED_VOTES)
		return;

	dev_warn(&data->client->dev,
		 "%s: %d.%d %% implies %d mV, terminals say %d mV at %d mA (OCV ~%d mV) - seeding\n",
		 data->need_seed ? "gauge never seeded for this battery"
				 : "reported SOC cannot be true",
		 data->soc / 10, data->soc % 10, curve_uv / 1000,
		 data->voltage / 1000, data->batt_current / 1000, ocv_uv / 1000);

	if (stc3117_seed(data, ocv_uv))
		dev_err(&data->client->dev, "seeding the gauge failed\n");
	else
		data->need_seed = false;
	data->seed_votes = 0;
}

static int stc3117_init(struct stc3117_data *data)
{
	int id, ret;
	int ctrl;
	int ocv_m, ocv_l;

	regmap_read(data->regmap, STC3117_ADDR_ID, &id);
	if (id != STC3117_ID)
		return -EINVAL;

	data->cc_cnf = (data->battery_info.battery_capacity_mah *
			data->battery_info.sense_resistor * 250 + 6194) / 12389;
	data->vm_cnf = (data->battery_info.battery_capacity_mah
					* data->rint_mohm * 50 + 24444) / 48889;

	/* Battery has not been removed */
	data->presence = 1;

	/*
	 * Battery-backed RAM: survives reboots and the I2C mux handing the
	 * gauge to the ESP32, but not unplugging the pack.
	 */
	ret = ram_read(data);
	if (ret)
		return ret;

	/*
	 * Read-only takeover: if the gauge is already running (GG_RUN set) and
	 * reports neither BATFAIL nor PORDET, somebody (boot ROM state, another
	 * MCU behind an I2C mux, a previous driver instance) has configured it
	 * and the coulomb counter holds valid state. Do not rewrite the OCV
	 * table / CNF registers and never GG_RST - just read it.
	 *
	 * Whether that state is worth anything is a separate question, and one
	 * a single sample cannot answer (see STC3117_SEED_VOTES), so it is left
	 * to the polling task. All that is decided here is whether this driver
	 * has ever seeded the gauge for this battery: without the mark in the
	 * battery-backed RAM the SOC is meaningless. A gauge the ESP32-S3
	 * started without anyone writing REG_OCV/REG_SOC counts coulombs up
	 * from 0 %, so a freshly flashed deck sits at 6 % with a 4.07 V pack
	 * and nothing downstream can tell that apart from a flat battery.
	 */
	{
		int mode0;

		ret = regmap_read(data->regmap, STC3117_ADDR_MODE, &mode0);
		ret |= regmap_read(data->regmap, STC3117_ADDR_CTRL, &ctrl);
		if (ret)
			return ret;
		if ((mode0 & STC3117_GG_RUN) &&
		    !(ctrl & (STC3117_BATFAIL | STC3117_PORDET))) {
			data->takeover = true;
			data->need_seed =
				data->ram_data.reg.seed_mark != STC3117_SEED_MARK;
			dev_info(&data->client->dev,
				 "gauge already running (mode=0x%02x ctrl=0x%02x), read-only takeover%s\n",
				 mode0, ctrl,
				 data->need_seed ? ", unseeded - will seed from voltage" : "");
		}
	}

	if (data->takeover) {
		/* adopt whatever is there; keep our bookkeeping in RAM only */
		data->ram_data.reg.testword = STC3117_RAM_TESTWORD;
		data->ram_data.reg.cc_cnf = data->cc_cnf;
		data->ram_data.reg.vm_cnf = data->vm_cnf;
	} else if (data->ram_data.reg.testword != STC3117_RAM_TESTWORD ||
	    (crc8(stc3117_crc_table, data->ram_data.ram_bytes,
					STC3117_RAM_SIZE, CRC8_INIT)) != 0) {
		data->ram_data.reg.testword = STC3117_RAM_TESTWORD;
		data->ram_data.reg.cc_cnf = data->cc_cnf;
		data->ram_data.reg.vm_cnf = data->vm_cnf;
		data->ram_data.reg.crc = crc8(stc3117_crc_table,
						data->ram_data.ram_bytes,
						STC3117_RAM_SIZE - 1, CRC8_INIT);

		ret = regmap_read(data->regmap, STC3117_ADDR_OCV_H, &ocv_m);

		ret |= regmap_read(data->regmap, STC3117_ADDR_OCV_L, &ocv_l);

		ret |= stc3117_set_para(data);

		ret |= regmap_write(data->regmap, STC3117_ADDR_OCV_H, ocv_m);

		ret |= regmap_write(data->regmap, STC3117_ADDR_OCV_L, ocv_l);
		if (ret)
			return ret;
	} else {
		ret = regmap_read(data->regmap, STC3117_ADDR_CTRL, &ctrl);
		if (ret)
			return ret;

		if ((ctrl & STC3117_BATFAIL) != 0  ||
		    (ctrl & STC3117_PORDET) != 0) {
			ret = regmap_read(data->regmap,
					  STC3117_ADDR_OCV_H, &ocv_m);

			ret |= regmap_read(data->regmap,
						STC3117_ADDR_OCV_L, &ocv_l);

			ret |= stc3117_set_para(data);

			ret |= regmap_write(data->regmap,
						STC3117_ADDR_OCV_H, ocv_m);

			ret |= regmap_write(data->regmap,
						STC3117_ADDR_OCV_L, ocv_l);
			if (ret)
				return ret;
		} else {
			ret = stc3117_set_para(data);
			ret |= regmap_write(data->regmap, STC3117_ADDR_SOC_H,
				     (data->ram_data.reg.hrsoc >> 8 & 0xFF));
			ret |= regmap_write(data->regmap, STC3117_ADDR_SOC_L,
				     (data->ram_data.reg.hrsoc & 0xFF));
			if (ret)
				return ret;
		}
	}

	data->ram_data.reg.state = STC3117_INIT;
	/* every path but the takeover has just configured and seeded the gauge */
	if (!data->takeover)
		data->ram_data.reg.seed_mark = STC3117_SEED_MARK;
	data->ram_data.reg.crc = crc8(stc3117_crc_table,
					data->ram_data.ram_bytes,
					STC3117_RAM_SIZE - 1, CRC8_INIT);
	ret = ram_write(data);
	if (ret)
		return ret;

	return 0;
};

static int stc3117_task(struct stc3117_data *data)
{
	int id, mode, ret;
	int count_l, count_m;
	int ocv_l, ocv_m;

	if (!data->inited) {
		if (stc3117_init(data))
			return -ENODEV;
		data->inited = true;
		dev_info(&data->client->dev, "gauge reachable again, initialised\n");
	}

	id = 0;
	ret = regmap_read(data->regmap, STC3117_ADDR_ID, &id);
	if (ret || id != STC3117_ID) {
		/*
		 * Not answering is not "battery removed": on the TypixDeck the I2C
		 * mux hands the gauge to the ESP32 whenever it owns the screen.
		 * Keep PRESENT and the last readings (upower would otherwise drop
		 * the battery); only BATFAIL below means removal.
		 */
		/* force a full re-init (takeover check) when it comes back */
		data->inited = false;
		return -EINVAL;
	}

	stc3117_get_battery_data(data);

	/* Read RAM data */
	ret = ram_read(data);
	if (ret)
		return ret;

	if (data->ram_data.reg.testword != STC3117_RAM_TESTWORD ||
	    (crc8(stc3117_crc_table, data->ram_data.ram_bytes,
					STC3117_RAM_SIZE, CRC8_INIT) != 0)) {
		data->ram_data.reg.testword = STC3117_RAM_TESTWORD;
		data->ram_data.reg.cc_cnf = data->cc_cnf;
		data->ram_data.reg.vm_cnf = data->vm_cnf;
		data->ram_data.reg.crc = crc8(stc3117_crc_table,
						data->ram_data.ram_bytes,
						STC3117_RAM_SIZE - 1, CRC8_INIT);
		data->ram_data.reg.state = STC3117_INIT;
	}

	/* check battery presence status */
	ret = regmap_read(data->regmap, STC3117_ADDR_CTRL, &mode);
	if ((mode & STC3117_BATFAIL) != 0) {
		data->presence = 0;
		data->ram_data.reg.testword = 0;
		data->ram_data.reg.state = STC3117_INIT;
		ret = ram_write(data);
		ret |= regmap_write(data->regmap, STC3117_ADDR_CTRL, STC3117_PORDET);
		if (ret)
			return ret;
	}

	data->presence = 1;

	ret = regmap_read(data->regmap, STC3117_ADDR_MODE, &mode);
	if (ret)
		return ret;
	if ((mode & STC3117_GG_RUN) == 0 && data->takeover) {
		/* the other master stopped the gauge; leave it alone */
		data->ram_data.reg.state = STC3117_INIT;
	} else if ((mode & STC3117_GG_RUN) == 0) {
		if (data->ram_data.reg.state > STC3117_INIT) {
			ret = stc3117_set_para(data);

			ret |= regmap_write(data->regmap, STC3117_ADDR_SOC_H,
					(data->ram_data.reg.hrsoc >> 8 & 0xFF));
			ret |= regmap_write(data->regmap, STC3117_ADDR_SOC_L,
					(data->ram_data.reg.hrsoc & 0xFF));
			if (ret)
				return ret;
		} else {
			ret = regmap_read(data->regmap, STC3117_ADDR_OCV_H, &ocv_m);

			ret |= regmap_read(data->regmap, STC3117_ADDR_OCV_L, &ocv_l);

			ret |= stc3117_set_para(data);

			ret |= regmap_write(data->regmap, STC3117_ADDR_OCV_H, ocv_m);

			ret |= regmap_write(data->regmap, STC3117_ADDR_OCV_L, ocv_l);
			if (ret)
				return ret;
		}
		data->ram_data.reg.state = STC3117_INIT;
	}

	regmap_read(data->regmap, STC3117_ADDR_COUNTER_L, &count_l);
	regmap_read(data->regmap, STC3117_ADDR_COUNTER_H, &count_m);

	count_m = (count_m << 8) + count_l;

	/* INIT state, wait for batt_current & temperature value available: */
	if (data->ram_data.reg.state == STC3117_INIT && count_m > 4) {
		data->avg_voltage = data->voltage;
		data->avg_current = data->batt_current;
		data->ram_data.reg.state = STC3117_RUNNING;
	}

	/*
	 * Only once the chip has settled: GG_RST zeroes the conversion counter,
	 * so this also keeps a fresh seed from being voted on before the gauge
	 * has had a chance to act on it.
	 */
	if (data->ram_data.reg.state == STC3117_RUNNING)
		stc3117_seed_check(data);

	if (data->ram_data.reg.state != STC3117_RUNNING) {
		data->batt_current = -ENODATA;
		data->temp = -ENODATA;
	} else {
		if (data->voltage < APP_CUTOFF_VOLTAGE)
			data->soc = -ENODATA;

		if (mode & STC3117_VMODE) {
			data->avg_current = -ENODATA;
			data->batt_current = -ENODATA;
		}
	}

	data->ram_data.reg.hrsoc = data->hrsoc;
	data->ram_data.reg.soc = (data->soc + 5) / 10;
	data->ram_data.reg.crc = crc8(stc3117_crc_table,
					data->ram_data.ram_bytes,
					STC3117_RAM_SIZE - 1, CRC8_INIT);

	ret = ram_write(data);
	if (ret)
		return ret;
	return 0;
};

static void fuel_gauge_update_work(struct work_struct *work)
{
	struct stc3117_data *data =
		container_of(work, struct stc3117_data, update_work.work);

	stc3117_task(data);

	/* Schedule the work to run again in 2 seconds */
	schedule_delayed_work(&data->update_work, msecs_to_jiffies(2000));
}

static int stc3117_get_property(struct power_supply *psy,
	enum power_supply_property psp, union power_supply_propval *val)
{
	struct stc3117_data *data = power_supply_get_drvdata(psy);

	switch (psp) {
	case POWER_SUPPLY_PROP_STATUS:
		/* data->soc is in tenths of a percent; current: + = charging */
		if (data->batt_current == -ENODATA)
			val->intval = POWER_SUPPLY_STATUS_UNKNOWN;
		else if (data->batt_current > 0 && (data->soc + 5) / 10 >= BATTERY_FULL)
			val->intval = POWER_SUPPLY_STATUS_FULL;
		else if (data->batt_current > 0)
			val->intval = POWER_SUPPLY_STATUS_CHARGING;
		else if (data->batt_current < 0)
			val->intval = POWER_SUPPLY_STATUS_DISCHARGING;
		else
			val->intval = POWER_SUPPLY_STATUS_NOT_CHARGING;
		break;
	case POWER_SUPPLY_PROP_VOLTAGE_NOW:
		val->intval = data->voltage;
		break;
	case POWER_SUPPLY_PROP_CURRENT_NOW:
		val->intval = data->batt_current;
		break;
	case POWER_SUPPLY_PROP_VOLTAGE_OCV:
		val->intval = data->ocv;
		break;
	case POWER_SUPPLY_PROP_CURRENT_AVG:
		val->intval = data->avg_current;
		break;
	case POWER_SUPPLY_PROP_CAPACITY:
		/* tenths of a percent -> percent, clamped */
		if (data->soc == -ENODATA)
			return -ENODATA;
		val->intval = clamp((data->soc + 5) / 10, 0, 100);
		break;
	/*
	 * charge_* in uAh: panel battery plugins (wfplug-batt / lxpanel batt)
	 * ignore "capacity" and compute the percentage as charge_now /
	 * charge_full, so without these the desktop shows 0 %. The gauge does
	 * not learn capacity, so full = design (simple-battery in the overlay).
	 */
	case POWER_SUPPLY_PROP_CHARGE_FULL_DESIGN:
	case POWER_SUPPLY_PROP_CHARGE_FULL:
		val->intval = data->battery_info.battery_capacity_mah * 1000;
		break;
	case POWER_SUPPLY_PROP_CHARGE_NOW:
		if (data->soc == -ENODATA)
			return -ENODATA;
		/* mAh * 1000 * (tenths of a percent / 1000) */
		val->intval = data->battery_info.battery_capacity_mah *
			      clamp(data->soc, 0, MAX_SOC);
		break;
	case POWER_SUPPLY_PROP_TEMP:
		val->intval = data->temp;
		break;
	case POWER_SUPPLY_PROP_PRESENT:
		val->intval = data->presence;
		break;
	default:
		return -EINVAL;
	}
	return 0;
}

static enum power_supply_property stc3117_battery_props[] = {
	POWER_SUPPLY_PROP_STATUS,
	POWER_SUPPLY_PROP_VOLTAGE_NOW,
	POWER_SUPPLY_PROP_CURRENT_NOW,
	POWER_SUPPLY_PROP_VOLTAGE_OCV,
	POWER_SUPPLY_PROP_CURRENT_AVG,
	POWER_SUPPLY_PROP_CAPACITY,
	POWER_SUPPLY_PROP_CHARGE_FULL_DESIGN,
	POWER_SUPPLY_PROP_CHARGE_FULL,
	POWER_SUPPLY_PROP_CHARGE_NOW,
	POWER_SUPPLY_PROP_TEMP,
	POWER_SUPPLY_PROP_PRESENT,
};

static const struct power_supply_desc stc3117_battery_desc = {
	.name = "stc3117-battery",
	.type = POWER_SUPPLY_TYPE_BATTERY,
	.get_property = stc3117_get_property,
	.properties = stc3117_battery_props,
	.num_properties = ARRAY_SIZE(stc3117_battery_props),
};

static const struct regmap_config stc3117_regmap_config = {
	.reg_bits       = 8,
	.val_bits       = 8,
};

static int stc3117_probe(struct i2c_client *client)
{
	struct stc3117_data *data;
	struct power_supply_config psy_cfg = {};
	struct power_supply_battery_info *info;
	int ret;

	data = devm_kzalloc(&client->dev, sizeof(*data), GFP_KERNEL);
	if (!data)
		return -ENOMEM;

	data->client = client;
	data->regmap = devm_regmap_init_i2c(client, &stc3117_regmap_config);
	if (IS_ERR(data->regmap))
		return PTR_ERR(data->regmap);

	psy_cfg.drv_data = data;
	psy_cfg.fwnode = dev_fwnode(&client->dev);

	crc8_populate_msb(stc3117_crc_table, CRC8_POLYNOMIAL);

	data->battery = devm_power_supply_register(&client->dev,
					&stc3117_battery_desc, &psy_cfg);
	if (IS_ERR(data->battery))
		return dev_err_probe(&client->dev, PTR_ERR(data->battery),
					"failed to register battery\n");

	ret = device_property_read_u32(&client->dev, "shunt-resistor-micro-ohms",
					&data->battery_info.sense_resistor);
	if (ret)
		return dev_err_probe(&client->dev, ret,
				"failed to get shunt-resistor-micro-ohms\n");
	data->battery_info.sense_resistor = data->battery_info.sense_resistor / 1000;

	ret = power_supply_get_battery_info(data->battery, &info);
	if (ret)
		return dev_err_probe(&client->dev, ret,
					"failed to get battery information\n");

	data->battery_info.battery_capacity_mah = info->charge_full_design_uah / 1000;
	data->rint_mohm = 200;
	if (info->factory_internal_resistance_uohm > 0)
		data->rint_mohm = info->factory_internal_resistance_uohm / 1000;
	data->battery_info.voltage_min_mv = info->voltage_min_design_uv / 1000;
	data->battery_info.voltage_max_mv = info->voltage_max_design_uv / 1000;

	/*
	 * The gauge may be unreachable right now (TypixDeck: I2C mux switched to
	 * the ESP32 side). Do not fail probe; the 2 s poll retries init until
	 * the chip answers and reports PRESENT=0 meanwhile.
	 */
	ret = stc3117_init(data);
	if (ret) {
		dev_warn(&client->dev,
			 "gauge not reachable (%d), will keep retrying\n", ret);
		data->presence = 0;
		data->soc = -ENODATA;
		data->batt_current = -ENODATA;
		data->temp = -ENODATA;
	} else {
		data->inited = true;
	}

	ret = devm_delayed_work_autocancel(&client->dev, &data->update_work,
					   fuel_gauge_update_work);
	if (ret)
		return ret;

	schedule_delayed_work(&data->update_work, 0);

	return 0;
}

static const struct i2c_device_id stc3117_id[] = {
	{ "stc3117", 0 },
	{ }
};
MODULE_DEVICE_TABLE(i2c, stc3117_id);

static const struct of_device_id stc3117_of_match[] = {
	{ .compatible = "st,stc3117" },
	{ }
};
MODULE_DEVICE_TABLE(of, stc3117_of_match);

static struct i2c_driver stc3117_i2c_driver = {
	.driver = {
		.name = "stc3117_i2c_driver",
		.of_match_table = stc3117_of_match,
	},
	.probe = stc3117_probe,
	.id_table = stc3117_id,
};

module_i2c_driver(stc3117_i2c_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Hardevsinh Palaniya <hardevsinh.palaniya@siliconsignals.io>");
MODULE_AUTHOR("Bhavin Sharma <bhavin.sharma@siliconsignals.io>");
MODULE_DESCRIPTION("STC3117 Fuel Gauge Driver");
