/*
 * xparameters_compat.h
 * Compatibility defines for migrating from Vivado 2019.1 SDK to Vitis 2025.2 SDT flow.
 *
 * In SDT mode, *_LookupConfig() takes base address instead of device ID index.
 * Interrupt IDs for PS peripherals remain the same (hardware hasn't changed).
 */

#ifndef XPARAMETERS_COMPAT_H
#define XPARAMETERS_COMPAT_H

#include "xparameters.h"

/* ScuGIC: device index 0 → base address */
#define XPAR_PS7_SCUGIC_0_DEVICE_ID         XPAR_XSCUGIC_0_BASEADDR

/* PS GPIO: device index 0 → base address, interrupt ID unchanged */
#define XPAR_PS7_GPIO_0_DEVICE_ID           XPAR_XGPIOPS_0_BASEADDR
#define XPAR_PS7_GPIO_0_INTR                52U   /* Zynq GIC SPI #52 */

/* PS I2C0: device index 0 → base address, interrupt ID unchanged */
#define XPAR_PS7_I2C_0_DEVICE_ID            XPAR_XIICPS_0_BASEADDR
#define XPAR_PS7_I2C_0_INTR                 57U   /* Zynq GIC SPI #57 */

/* AXI VDMA: device index 0 → base address */
#define XPAR_AXIVDMA_0_DEVICE_ID            XPAR_AXI_VDMA_0_BASEADDR

/* AXI VDMA interrupt names changed */
#define XPAR_FABRIC_AXI_VDMA_0_MM2S_INTROUT_INTR   XPAR_FABRIC_AXI_VDMA_0_INTR
#define XPAR_FABRIC_AXI_VDMA_0_S2MM_INTROUT_INTR   XPAR_FABRIC_AXI_VDMA_0_INTR_1

/* VTC: device index 0 → base address */
#define XPAR_VTC_0_DEVICE_ID                XPAR_XVTC_0_BASEADDR

/* Video DynClk: device index 0 → base address */
#define XPAR_VIDEO_DYNCLK_DEVICE_ID         XPAR_VIDEO_DYNCLK_BASEADDR

/* DDR base address renamed */
#define XPAR_DDR_MEM_BASEADDR               XPAR_PS7_DDR_0_BASEADDRESS

/* MIPI AXI-Lite base address renamed */
#define XPAR_MIPI_CSI_2_RX_0_S_AXI_LITE_BASEADDR   XPAR_MIPI_CSI_2_RX_0_BASEADDR
#define XPAR_MIPI_D_PHY_RX_0_S_AXI_LITE_BASEADDR   XPAR_MIPI_D_PHY_RX_0_BASEADDR

/* GammaCorrection base address unchanged */
/* XPAR_AXI_GAMMACORRECTION_0_BASEADDR is already defined in xparameters.h */

/* AXI_ImageModeSelect base address */
#define IMAGE_MODE_SELECT_BASEADDR  XPAR_AXI_IMAGEMODESELECT_1_BASEADDR

/* AXI GPIO (button) base address */
#define BUTTON_GPIO_BASEADDR        XPAR_AXI_GPIO_0_BASEADDR

#endif /* XPARAMETERS_COMPAT_H */
