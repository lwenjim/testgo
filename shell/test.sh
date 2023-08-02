#!/bin/sh

echo the date is "$(date)" 
eval set -- "$(date)"
echo the month is $2