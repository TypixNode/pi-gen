# Out-of-tree build of the mainline STC3117 fuel gauge driver
# (drivers/power/supply/stc3117_fuel_gauge.c, Linux v6.18, GPL-2.0).
# Raspberry Pi OS kernels ship CONFIG_FUEL_GAUGE_STC3117 unset, so we build
# the same source as a module against the Pi's linux-headers package.
#
#   make KDIR=/lib/modules/<kver>/build        # native or in the arm64 container
#
ifneq ($(KERNELRELEASE),)
obj-m += stc3117_fuel_gauge.o
else
KDIR ?= /lib/modules/$(shell uname -r)/build
all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
endif
