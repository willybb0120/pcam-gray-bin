#include "xparameters_compat.h"

#include "platform/platform.h"
#include "ov5640/OV5640.h"
#include "ov5640/ScuGicInterruptController.h"
#include "ov5640/PS_GPIO.h"
#include "ov5640/AXI_VDMA.h"
#include "ov5640/PS_IIC.h"

#include "MIPI_D_PHY_RX.h"
#include "MIPI_CSI_2_RX.h"
#include "xgpio.h"
#include "sleep.h"


#define IRPT_CTL_DEVID 		XPAR_PS7_SCUGIC_0_DEVICE_ID
#define GPIO_DEVID			XPAR_PS7_GPIO_0_DEVICE_ID
#define GPIO_IRPT_ID			XPAR_PS7_GPIO_0_INTR
#define CAM_I2C_DEVID		XPAR_PS7_I2C_0_DEVICE_ID
#define CAM_I2C_IRPT_ID		XPAR_PS7_I2C_0_INTR
#define VDMA_DEVID			XPAR_AXIVDMA_0_DEVICE_ID
#define VDMA_MM2S_IRPT_ID	XPAR_FABRIC_AXI_VDMA_0_MM2S_INTROUT_INTR
#define VDMA_S2MM_IRPT_ID	XPAR_FABRIC_AXI_VDMA_0_S2MM_INTROUT_INTR
#define CAM_I2C_SCLK_RATE	100000

#define DDR_BASE_ADDR		XPAR_DDR_MEM_BASEADDR
#define MEM_BASE_ADDR		(DDR_BASE_ADDR + 0x0A000000)

#define GAMMA_BASE_ADDR     XPAR_AXI_GAMMACORRECTION_0_BASEADDR

#define BUTTON_MASK         0x1U
#define IMG_MODE_THRESHOLD  128U    /* default binarization threshold */

using namespace digilent;

void pipeline_mode_change(AXI_VDMA<ScuGicInterruptController>& vdma_driver, OV5640& cam, VideoOutput& vid, Resolution res, OV5640_cfg::mode_t mode)
{
	//Bring up input pipeline back-to-front
	{
		vdma_driver.resetWrite();
		MIPI_CSI_2_RX_mWriteReg(XPAR_MIPI_CSI_2_RX_0_S_AXI_LITE_BASEADDR, CR_OFFSET, (CR_RESET_MASK & ~CR_ENABLE_MASK));
		MIPI_D_PHY_RX_mWriteReg(XPAR_MIPI_D_PHY_RX_0_S_AXI_LITE_BASEADDR, CR_OFFSET, (CR_RESET_MASK & ~CR_ENABLE_MASK));
		cam.reset();
	}

	{
		vdma_driver.configureWrite(timing[static_cast<int>(res)].h_active, timing[static_cast<int>(res)].v_active);
		Xil_Out32(GAMMA_BASE_ADDR, 3); // Set Gamma correction factor to 1/1.8
		//TODO CSI-2, D-PHY config here
		cam.init();
	}

	{
		vdma_driver.enableWrite();
		MIPI_CSI_2_RX_mWriteReg(XPAR_MIPI_CSI_2_RX_0_S_AXI_LITE_BASEADDR, CR_OFFSET, CR_ENABLE_MASK);
		MIPI_D_PHY_RX_mWriteReg(XPAR_MIPI_D_PHY_RX_0_S_AXI_LITE_BASEADDR, CR_OFFSET, CR_ENABLE_MASK);
		cam.set_mode(mode);
		cam.set_awb(OV5640_cfg::awb_t::AWB_ADVANCED);
	}

	//Bring up output pipeline back-to-front
	{
		vid.reset();
		vdma_driver.resetRead();
	}

	{
		vid.configure(res);
		vdma_driver.configureRead(timing[static_cast<int>(res)].h_active, timing[static_cast<int>(res)].v_active);
	}

	{
		vid.enable();
		vdma_driver.enableRead();
	}
}

int main()
{
	init_platform();

	ScuGicInterruptController irpt_ctl(IRPT_CTL_DEVID);
	PS_GPIO<ScuGicInterruptController> gpio_driver(GPIO_DEVID, irpt_ctl, GPIO_IRPT_ID);
	PS_IIC<ScuGicInterruptController> iic_driver(CAM_I2C_DEVID, irpt_ctl, CAM_I2C_IRPT_ID, 100000);

	OV5640 cam(iic_driver, gpio_driver);
	AXI_VDMA<ScuGicInterruptController> vdma_driver(VDMA_DEVID, MEM_BASE_ADDR, irpt_ctl,
			VDMA_MM2S_IRPT_ID,
			VDMA_S2MM_IRPT_ID);
	VideoOutput vid(XPAR_VTC_0_DEVICE_ID, XPAR_VIDEO_DYNCLK_DEVICE_ID);

	pipeline_mode_change(vdma_driver, cam, vid, Resolution::R1920_1080_60_PP, OV5640_cfg::mode_t::MODE_1080P_1920_1080_30fps);

	xil_printf("Video init done.\r\n");

	// Init AXI GPIO for BTN0
	XGpio gpio_btn;
	XGpio_Initialize(&gpio_btn, BUTTON_GPIO_BASEADDR);
	XGpio_SetDataDirection(&gpio_btn, 1, 0xFFFFFFFFU); // channel 1 all inputs

	// Set initial image mode: 0=original, write threshold default
	u32 img_mode = 0;
	Xil_Out32(IMAGE_MODE_SELECT_BASEADDR,      img_mode);
	Xil_Out32(IMAGE_MODE_SELECT_BASEADDR + 4,  IMG_MODE_THRESHOLD);
	xil_printf("Image mode: 0 (original). Press BTN0 to cycle.\r\n");

	u32 btn_prev = 0;
	while (1) {
		u32 btn = XGpio_DiscreteRead(&gpio_btn, 1) & BUTTON_MASK;
		if (btn && !btn_prev) {
			img_mode = (img_mode + 1) % 3;
			Xil_Out32(IMAGE_MODE_SELECT_BASEADDR, img_mode);
			const char* mode_str = (img_mode == 0) ? "original" :
			                       (img_mode == 1) ? "grayscale" : "binary";
			xil_printf("Image mode: %d (%s)\r\n", (int)img_mode, mode_str);
			usleep(200000); // 200ms debounce
		}
		btn_prev = btn;
		usleep(10000); // 10ms poll interval
	}


	cleanup_platform();

	return 0;
}
