# Broad_band_equalizer on Zynq-7020
A broad band equalizer implementing GAL-NLMS algorithm and running on Zynq-7020 FPGA.    
This is the Xilinx competition project I have done with my friend.       

# Resources
GAL.v: a naive version of GAL algorithm implementation on FPGA. Language is Verilog.         
GAL_NEW.v: a optimized version of GAL algorithm implemantation.    
report.pdf: the full report and technical detail of this project, if you can read Chinese.    
    

---
# More
NLMS part is not provided, it is running on ARM dule core, writing by C++.   
You can get a video introduction of this project if you understand Chinese:     
[Video show of this project](https://v.youku.com/v_show/id_XNTczODM1MzUy.html)      
      

Here is the GAL-NLMS algorithm:    
![](https://github.com/stephenkung/broad_band_equalizer/blob/master/GAL-NLMS.png)
