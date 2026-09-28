#!/bin/bash

find "${1:-.}" -type f ! -path '*/.*' -exec wc -l {} + | sort -nr

