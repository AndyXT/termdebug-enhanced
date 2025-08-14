#!/bin/bash

# Run tests for termdebug-enhanced plugin
# Usage: ./run_tests.sh

# set -e  # Don't exit on first error, we want to run all tests

echo "================================"
echo "Running termdebug-enhanced tests"
echo "================================"
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Track test results
TOTAL_PASSED=0
TOTAL_FAILED=0

# Function to run a test file
run_test() {
    local test_file=$1
    local test_name=$(basename "$test_file" .lua)
    
    echo "Running $test_name..."
    
    if nvim --headless -u NONE -c "set rtp+=." -l "$test_file" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ $test_name passed${NC}"
        ((TOTAL_PASSED++))
    else
        echo -e "${RED}✗ $test_name failed${NC}"
        # Show error output for failed tests
        echo "Error output:"
        nvim --headless -u NONE -c "set rtp+=." -l "$test_file" 2>&1 | sed 's/^/  /'
        ((TOTAL_FAILED++))
    fi
    echo
}

# Find and run all test files
for test_file in tests/test_*.lua; do
    if [ -f "$test_file" ]; then
        run_test "$test_file"
    fi
done

# Summary
echo "================================"
echo "Test Summary"
echo "================================"
if [ $TOTAL_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! ($TOTAL_PASSED tests)${NC}"
    exit 0
else
    echo -e "${RED}Tests failed: $TOTAL_FAILED${NC}"
    echo -e "${GREEN}Tests passed: $TOTAL_PASSED${NC}"
    exit 1
fi