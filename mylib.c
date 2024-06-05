#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <assert.h>


char* print(char* str)
{
    char* name;
    name = (char*)malloc(10);
    strcpy(name, str);
    return name;

}

char* print2(char* des, const char* source)
{
    char* r = des;
    assert((r != NULL) && (source != NULL));
    while ((*r++ = *source++)!= '\0');
    return des;
}

char* print3()
{
    static char name[10];
    strcpy(name, "柳松酒");
    return name;
}

char name[100];
char* print4()
{
    strcpy(name, "你好呀");
    return name;
}