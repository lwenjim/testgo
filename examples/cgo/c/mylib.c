#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// 定义一个函数，返回一个字符串
char* print(char* str) {
    char* name;
    name = (char*)malloc(10);
    strcpy(name, str);
    strcpy(name, "不错喔");
    return name;
}

// 定义一个函数，返回一个字符串，并将其拷贝到指定的字符串中
char* print2(char* des, const char* source) {
    char* r = des;
    assert((r != NULL) && (source != NULL));
    while ((*r++ = *source++) != '\0');
    return des;
}

// 定义一个静态变量，返回一个字符串
char* print3() {
    static char name[10];
    strcpy(name, "柳松酒");
    return name;
}

// 定义一个全局变量，返回一个字符串
char name[100];
char* print4() {
    strcpy(name, "你好呀");
    return name;
}
