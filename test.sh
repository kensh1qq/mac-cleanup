#!/bin/bash
# Все проверки: движок (selftest на фейковом HOME) + поиск программ и файлов на этом Mac.
set -euo pipefail
cd "$(dirname "$0")"
./cleanup selftest
mkdir -p build
swiftc -swift-version 5 -D TEST App.swift Tests.swift -o build/tests
./build/tests
