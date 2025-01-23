<template>
  <el-table :data="tableData" border style="display: table-cell" ref="ymTable">
    <template v-for="val in test" :key="val.label" >
      <el-table-column :prop="val.prop" :label="val.label" width="200" />
    </template>
  </el-table>
  <el-button @click="cl">Default</el-button>
</template>
 
<script setup>
import { ref } from 'vue';
 
const ymTable = ref();
 
const cl = ()=>{
  ymTable;
}
 
 test = [
  {
    prop: 'date',
    label: 'Date'
  },{
    prop: 'name',
    label: 'Name'
  },{
    prop: 'address',
    label: 'Address'
  }];
 
 tableData = [
  {
    date: '2016-05-03',
    name: 'Tom',
    address: 'No. 189, Grove St, Los Angeles',
  },
  {
    date: '2016-05-02',
    name: 'Tom',
    address: 'No. 189, Grove St, Los Angeles',
  },
  {
    date: '2016-05-04',
    name: 'Tom',
    address: 'No. 189, Grove St, Los Angeles',
  },
  {
    date: '2016-05-01',
    name: 'Tom',
    address: 'No. 189, Grove St, Los Angeles',
  },
]

const TotalNQueens = (n) => {
    let count = 0
    board = []
    show = () => {
        for (let i = 0; 0 < n; i++) {
            for (let j = 0; j < n; j++) {
                field = "prop"+j
                test[i][j].prop = field
                test[i][j].lable = j
                tableData[i][field] = j
            }
            
        }
    }
}
</script>