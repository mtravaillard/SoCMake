# Examples :
This table present the examples and the tools that they support:
<div align="center">

|            Example            |    No EDA needed   |       Questa       |         VCS        |       XCelium      |      Verilator     |      Iverilog      |        GHDL        |   Vivado  |
| :---------------------------: | :----------------: | :----------------: | :----------------: | :----------------: | :----------------: | :----------------: | :----------------: | :-------: |
|              cpm              | :heavy_check_mark: |                    |                    |                    |                    |                    |                    |           |
|             dpi-c             |                    | :heavy_check_mark: | :heavy_check_mark: | :heavy_check_mark: | :heavy_check_mark: |                    |                    | :warning: |
|          fecthcontent         | :heavy_check_mark: |                    |                    |                    |                    |                    |                    |           |
|          linking_ips          | :heavy_check_mark: |                    |                    |                    |                    |                    |                    |           |
|            modelsim           |                    |         :x:        |                    |                    |                    |                    |                    |           |
|            options            | :heavy_check_mark: |                    |                    |                    |                    |                    |                    |           |
|         simple_cocotb         |                    |                    | :heavy_check_mark: | :heavy_check_mark: | :heavy_check_mark: | :heavy_check_mark: |                    |           |
|     simple_mixed_language     |                    | :heavy_check_mark: | :heavy_check_mark: | :heavy_check_mark: |                    |                    |                    | :warning: |
| simple_mixed_language_sc_vlog |                    | :heavy_check_mark: | :heavy_check_mark: | :heavy_check_mark: |         :x:        |                    |                    |           |
|          simple_sc_sv         |                    |                    |                    |                    | :heavy_check_mark: |                    |                    |           |
|         simple_verilog        |                    | :heavy_check_mark: | :heavy_check_mark: | :heavy_check_mark: | :heavy_check_mark: | :heavy_check_mark: |                    | :warning: |
|          simple_vhdl          |                    | :heavy_check_mark: | :heavy_check_mark: | :heavy_check_mark: |                    |                    | :heavy_check_mark: | :warning: |
|            systemc            | :heavy_check_mark: |                    |                    |                    |                    |                    |                    |           |
|          uvm-systemc          | :heavy_check_mark: |                    |                    |                    |                    |                    |                    |           |
|           verilator           |                    |                    |                    |                    | :heavy_check_mark: |                    |                    |           |
|           vhpidirect          |                    | :heavy_check_mark: |                    |                    |                    |                    | :heavy_check_mark: |           |
</div>

:heavy_check_mark: : the example correctly run with the corresponding tool.\
:x: : the example is currently not working with the corresponding tool.\
:warning: the example can run with the tool but has not been verified.\
blank space : the example does not use the corresponding tool.