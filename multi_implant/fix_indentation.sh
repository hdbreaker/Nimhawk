#!/bin/bash

# Fix common indentation issues in main.nim
sed -i '' '
# Fix when defined debug statements that are incorrectly indented
s/^                                        when defined debug:$/                                    when defined debug:/g
s/^                                        echo "\[DEBUG\]/                                        echo "[DEBUG]/g
s/^                                            when defined debug:$/                                        when defined debug:/g
s/^                                            echo "\[DEBUG\]/                                            echo "[DEBUG]/g
' main.nim

echo "Fixed indentation issues"
