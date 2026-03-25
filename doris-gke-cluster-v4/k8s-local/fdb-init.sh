#!/bin/bash
echo "configure new single s" | fdbcli
fdbcli --exec "status"
