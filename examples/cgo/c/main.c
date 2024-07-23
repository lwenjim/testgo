#include <stdio.h>

#include "mylib.h"

int main(int argc, char const *argv[]) {
    char *s1 = "Hello, world!";
    char *str = print(s1);
    printf("%s\n", str);

    char *des;
    char *src = "Hello, world!";
    char *res = print2(des, src);
    printf("res: %s\n", res);
    printf("des: %s\n", des);

    char *res2 = print3();
    printf("res2: %s\n", res2);

    char *res3 = print4();
    printf("res3: %s\n", res3);

    return 0;
}
