# ---- clock (200MHz LVDS osc, bank 34 VCCO = 1.35V) ----
set_property -dict {PACKAGE_PIN R4 IOSTANDARD DIFF_SSTL135} [get_ports clkin_p]

# ---- LED ----
set_property -dict {PACKAGE_PIN W22 IOSTANDARD LVCMOS33} [get_ports led]

# ---- DAC128S085 (PZ7606 on JM2 pin 37-40) ----
set_property -dict {PACKAGE_PIN L19 IOSTANDARD LVCMOS33} [get_ports sync]
set_property -dict {PACKAGE_PIN M18 IOSTANDARD LVCMOS33} [get_ports sck]
set_property -dict {PACKAGE_PIN L20 IOSTANDARD LVCMOS33} [get_ports miso]
set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33} [get_ports mosi]

# ---- AD7606 control (PZ7606 on JM2) ----
# !! JM2 pin 5 (G17) is GND on the PZ7606 side : never assign / drive G17 !!
set_property -dict {PACKAGE_PIN N22 IOSTANDARD LVCMOS33} [get_ports adc_convst]
set_property -dict {PACKAGE_PIN G18 IOSTANDARD LVCMOS33} [get_ports adc_reset]
set_property -dict {PACKAGE_PIN M22 IOSTANDARD LVCMOS33} [get_ports adc_rd_n]
set_property -dict {PACKAGE_PIN G15 IOSTANDARD LVCMOS33} [get_ports adc_cs_n]
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports adc_busy]
set_property -dict {PACKAGE_PIN G16 IOSTANDARD LVCMOS33} [get_ports adc_frstdata]
set_property -dict {PACKAGE_PIN H19 IOSTANDARD LVCMOS33} [get_ports adc_range]
set_property -dict {PACKAGE_PIN K22 IOSTANDARD LVCMOS33} [get_ports adc_par_ser]
set_property -dict {PACKAGE_PIN K19 IOSTANDARD LVCMOS33} [get_ports {adc_os[0]}]
set_property -dict {PACKAGE_PIN J22 IOSTANDARD LVCMOS33} [get_ports {adc_os[1]}]
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports {adc_os[2]}]

# ---- AD7606 data ----
set_property -dict {PACKAGE_PIN H18 IOSTANDARD LVCMOS33} [get_ports {adc_db[0]}]
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS33} [get_ports {adc_db[1]}]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports {adc_db[2]}]
set_property -dict {PACKAGE_PIN H14 IOSTANDARD LVCMOS33} [get_ports {adc_db[3]}]
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports {adc_db[4]}]
set_property -dict {PACKAGE_PIN H13 IOSTANDARD LVCMOS33} [get_ports {adc_db[5]}]
set_property -dict {PACKAGE_PIN M21 IOSTANDARD LVCMOS33} [get_ports {adc_db[6]}]
set_property -dict {PACKAGE_PIN G13 IOSTANDARD LVCMOS33} [get_ports {adc_db[7]}]
set_property -dict {PACKAGE_PIN L21 IOSTANDARD LVCMOS33} [get_ports {adc_db[8]}]
set_property -dict {PACKAGE_PIN J20 IOSTANDARD LVCMOS33} [get_ports {adc_db[9]}]
set_property -dict {PACKAGE_PIN H20 IOSTANDARD LVCMOS33} [get_ports {adc_db[10]}]
set_property -dict {PACKAGE_PIN J21 IOSTANDARD LVCMOS33} [get_ports {adc_db[11]}]
set_property -dict {PACKAGE_PIN G20 IOSTANDARD LVCMOS33} [get_ports {adc_db[12]}]
set_property -dict {PACKAGE_PIN J19 IOSTANDARD LVCMOS33} [get_ports {adc_db[13]}]
set_property -dict {PACKAGE_PIN K21 IOSTANDARD LVCMOS33} [get_ports {adc_db[14]}]
set_property -dict {PACKAGE_PIN H22 IOSTANDARD LVCMOS33} [get_ports {adc_db[15]}]

# ---- AD7606 I/O is slow & handled by FSM timing : no timing analysis needed ----
set_false_path -to [get_ports {adc_convst adc_reset adc_cs_n adc_rd_n adc_range adc_par_ser {adc_os[*]}}]
set_false_path -from [get_ports {adc_busy adc_frstdata {adc_db[*]}}]
set_false_path -to [get_ports {sync sck mosi led}]
set_false_path -from [get_ports miso]

