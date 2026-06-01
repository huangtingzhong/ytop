-- File Name: gv_vm.sql
-- Purpose: YashanDB Show global VM and SGA memory summary
-- Created: 20260516  by  huangtingzhong

select inst_id,TOTAL_BLOCKS,FREE_BLOCKS,OPENED_BLOCKS,CLOSED_BLOCKS,SWAPPED_OUT_BLOCKS,CTRL_BLOCKS,FREE_SWAP_BLOCKS from gv$vm;
