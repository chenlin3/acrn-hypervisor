/*
 * Copyright (C) 2018 Intel Corporation. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *   * Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in
 *     the documentation and/or other materials provided with the
 *     distribution.
 *   * Neither the name of Intel Corporation nor the names of its
 *     contributors may be used to endorse or promote products derived
 *     from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */



#include <types.h>
#include <acpi.h>
#include <logmsg.h>

#ifdef HV_DEBUG

uint64_t get_acpi_tbl(char *sig);

#define ACPI_SIG_DBGP	"DBGP"
#define ACPI_SIG_DBG2	"DBG2"
#define ACPI_SIG_SPCR	"SPCR"

/* Debug port type */
#define DBG2_PORT_TYPE_16550	0x8000
#define DBG2_PORT_SUBTYPE_v2	0x0000
#define DBG2_PORT_SUBTYPE_v1	0x0001

/* ACPI Space Address type I/O or Memory */
#define ACPI_GAS_TYPE_IO	0
#define ACPI_GAS_TYPE_MEM	1

/* ACPI generic address structure */
typedef struct acpi_gas_addr {
	uint8_t		space_id;
	uint8_t		bit_width;
	uint8_t		bit_offset;
	uint8_t		encode_width;
	uint64_t	addr;	
} acpi_gas_t;


struct dbg2_devinfo {
	uint8_t		rev_id;
	uint16_t	info_len;
	uint8_t		register_nums;
	uint16_t	namespace_len;
	uint16_t	oem_data_len;
	uint16_t	oem_data_offset;

	uint16_t	port_type;
	uint16_t	port_subtype;
	uint16_t	reserved;
	uint16_t	bar_offset;
	uint16_t	addr_size_offset;

	/*
	 * ACPI_GAS(12) base_addr_regs[];
	 * uint32_t addr_size[];
	 * char	namespace[];
	 * uint8_t oem_data[];
	 */
};

struct acpi_table_dbg2 {
	struct acpi_table_header	header;

	uint64_t	devinfo_offset;
	uint64_t	devinfo_nums;

	struct dbg2_devinfo	devinfo[0];
};


struct acpi_table_spcr {
	struct acpi_table_header	header;

	uint8_t		interface_type;
	uint8_t		reserved[3];

	uint8_t		space_id;
	uint8_t		width_bit;
	uint8_t		offset_bit;
	uint8_t		access_width;
	uint64_t	base_addr;

	uint8_t		intr_type;
	uint8_t		irq_num;
	uint32_t	gsi_num;
	uint8_t		baud_rate;	
	uint8_t		parity_bits;
	uint8_t		stop_bits;
	uint8_t		flow_ctrl_bits;
	uint8_t		reserved2;

	uint16_t	device_id;
	uint16_t	vendor_id;
	uint8_t		bus_num;
	uint8_t		device_num;
	uint8_t		func_num;
	uint32_t	pci_flags;
	uint8_t		pci_segment;
	uint32_t	reserved3;
};


int acpi_table_checksum(struct acpi_table_header *table)
{
	uint32_t	i = table->length;
	uint8_t		*buf = (uint8_t *)table;
	uint8_t		sum = 0;

	while (i > 0) {
		sum += *buf++;
		i--;
	}
	
	if (i != 0) {
		pr_err("ACPI %c%c%c%c table checksum failed",
			table->signature[0], table->signature[1],
			table->signature[2], table->signature[3]);
	}

	return i;
}


/*
 * Try to get a UART debug port from SPCR, DBG2, or DBGP ACPI table,
 * set the (I/O or mmio) addr of the debug port to uart driver. 
 * return 0 if succeed, others if failed.
 */
int  acpi_get_uart()
{
	struct acpi_table_spcr *spcr;
	struct acpi_table_dbg2 *dbg2;
	struct acpi_table_dbgp *dbgp;
	struct dbg2_devinfo *dev;
	struct acpi_gas_addr *bar;
	uint64_t	addr, size;
	uint32_t	nums, i;

	addr = get_acpi_tbl(ACPI_SIG_SPCR);
	if (addr != 0) {
		spcr = (struct acpi_table_spcr *)addr;
	}

	
	addr = get_acpi_tbl(ACPI_SIG_DBG2);
	if (addr != 0) {

		dbg2 = (struct acpi_table_dbg2 *)addr;
		dev = (struct dbg2_devinfo *)dbg2->devinfo_offset;
		nums =(struct dbg2_devinfo *)dbg2->devinfo_nums;

		/* 
		 * ACRN hypervisor supports UART, try to find such
		 * a compatible debug port/device to use as UART
		 * */
		for (i = 0; i < nums; i++) {
			if (dev->port_type != DBG2_PORT_TYPE_16550)
				continue;

			if ((dev->port_subtype != DBG2_PORT_SUBTYPE_v2) &&
			    (dev->port_subtype != DBG2_PORT_SUBTYPE_v1))
			       continue;

			if (dev->register_nums != 1)
				continue;

			size =  (uint64_t*)(addr + dev->addr_size_offset);
			if (size < 0x0C)
				continue;

			bar = (acpi_gas_t *)(addr + dev->bar_offset);
			if ((bar->space_id == ACPI_GAS_TYPE_IO) ||
			   (bar->space_id == ACPI_GAS_TYPE_MEM)) {
				uart16550_set_property(1, bar->space_id, addr);
				pr_info("Use ACPI DBG2 port as UART");
				return -1;
			}
		}
	}


	addr = get_acpi_tbl(ACPI_SIG_DBGP);
	if (addr != 0) {
		dbgp = (struct acpi_table_dbgp *)addr;
	}

	return 0;
}
#endif
