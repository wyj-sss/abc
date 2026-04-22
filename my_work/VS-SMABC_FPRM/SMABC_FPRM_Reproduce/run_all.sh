#!/bin/bash
set -e

gcc -o smabc main.c fprm.c smabc.c -lm
./smabc
echo "========================================"
echo "✅ 12个电路全部完成！"
echo "📄 网表文件: smabc_opt/*.v"
echo "========================================"