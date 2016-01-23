#!/bin/bash

# usage:
#  run_rhosqe_tests.sh <dir-with-tests> [fullname-where-to-create-junit-xml]
#
# all *.sh files in dir-with-tests will be executed, each of them as single testcase
#
# if not specified other path, this script creates ./nosetests.xml jUnit xml file
# describing the passed/failed testcases (eg. to be processed by jenkins)
#
# EXIT_SKIP and EXIT_DIRTY env variables are provided, their value should be used
# as exit code when testcase:
# - decides it should not run [SKIP]
# - it reaches state it cannot handle/clean after itself (failure in teardown ...) [DIRTY]
#


if [[ -z "$1" || ! -d "$1" ]]; then
    echo "You have to specify path to directory with testcases to run, as first argument." >&2
    exit 1
fi

#if [[ ! -z "$rhosqe_product" && ! -z "$rhosqe_version" ]]; then
#    "$(dirname "$0")/product-branch.sh"
#fi

TESTS_DIR="$1"
TESTS_DIR="${TESTS_DIR%/}"  # strip possible last slash from the end
TESTS_DIR="${TESTS_DIR/.\//}" # strip possible "./" from the beginning

export EXIT_SKIP=75  # code used by tests to announce their skipping
                      # value comes from EX_TEMPFAIL from /usr/include/sysexits.h
export EXIT_DIRTY=70  # code used by tests to announce they failed in cleanup/... part and the env may be dirty
                       # same as if they will time-out
                       # EX_SOFTWARE being used here
DEFAULT_TIMEOUT=5m  # can be overriden per testcase with '# testconfig: timeout=12m'
EXIT_TIMEDOUT=124  # ecode of timeout command
EXIT_TIMEDKILL=$(( 128 + 9 ))  # ecode of timeout command

JUNIT_FINAL="$(pwd)/nosetests.xml"
JUNIT="$(mktemp)"
TEST_LOG="$(mktemp)"
touch "$JUNIT"
trap "rm -f $JUNIT $TEST_LOG" EXIT
echo "Going to generate $JUNIT_FINAL (with temp file at $JUNIT)"
CONTROLLER1=${2:-""}
CONTROLLER2=${3:-""}
CONTROLLER3=${4:-""}

DRYRUN=${DRYRUN:-0}

START="$(date "+%s")"
TOTAL=0
SKIPPED=0
FAILURES=0
ERRORS=0

if [[ "${NO_COLOR:false}" = "true" ]]; then
    CLR_PASS=""; CLR_FAIL=""; CLR_ERR=""; CLR_NONE="";
else
    CLR_PASS="$(echo -e "\033[01;36m")"
    CLR_FAIL="$(echo -e "\033[00;31m")"
    CLR_ERR="$(echo -e "\033[01;31m")"
    CLR_NONE="$(echo -e "\033[00m")"
fi


config() {
    # usage: config <test-file> <key> [default_value=]
    local tfile=$1
    local key=$2
    local default=${3:-}
    local comment="#"
    # grep out testconfig line, with given key, if not find fake it with default value
    (grep -E "^\s*#\s+testconfig:.* ${key}=.*" $tfile || echo " ${key}=\"$default\"") | \
        sed -r "s/.* ${key}=(\"([^\"]*)\"|([^ ]*))($| .*$)/\2\3/"
    # and parse out the value with two possible cases
    # 1) key=value-without-whiespaces
    # 2) key="quoted value"
}
header() {
  echo "====== $TEST_CLASS: $1 ======"
}
safe4xml() {
    sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "$1"
}
finish() {
    cat > $JUNIT_FINAL <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite tests="${TOTAL}" errors="${ERRORS}" failures="${FAILURES}" skip="${SKIPPED}">
EOF
    [[ -f "$JUNIT" ]] && cat $JUNIT >> $JUNIT_FINAL
    cat >> $JUNIT_FINAL <<EOF
</testsuite>
EOF

    TEST_CLASS="RUNNER"
    header "Finished ${1:-}"
    header "Total/Errors/Failures/Skips: $TOTAL/$ERRORS/$FAILURES/$SKIPPED"
    header "in $(( $(date "+%s") - $START )) seconds"

    # we always want to exit with 0 in case test-runner worked properly
    # so the non zero means broken runner
    exit 0
}
junit_test() {
    cat >> $JUNIT <<EOF
    <testcase classname="$TEST_CLASS" name="$TEST_NAME" time="$TEST_TIME">$1</testcase>
EOF
}
test_passed() {
    junit_test ""

    header "${CLR_PASS}PASSED${CLR_NONE} in ${TEST_TIME}s"
}
test_skipped() {
    junit_test "<skipped>$(safe4xml "$TEST_LOG")</skipped>"

    SKIPPED=$(( $SKIPPED + 1 ))
    header "${CLR_PASS}SKIPPED${CLR_NONE}"
}
test_failed() {
    junit_test "<failure type=\"exitCode\" message=\"Exit code: $STATUS\">$(safe4xml "$TEST_LOG")</failure>"

    FAILURES=$(( $FAILURES + 1 ))
    header "${CLR_FAIL}FAILED${CLR_NONE} with code $STATUS in ${TEST_TIME}s"
}
test_erred() {
    junit_test "<error type=\"exitCode\" message=\"Exit code: $STATUS\">$(safe4xml "$TEST_LOG")</error>"

    ERRORS=$(( $ERRORS + 1 ))
    header "${CLR_ERR}ERROR${CLR_NONE} with code $STATUS in ${TEST_TIME}s"

    finish "early due to ERROR"
}
setupteardown_failed() {
    TEST_NAME="$1"
    STATUS="$2"
    TEST_TIME=0
    TEST_CLASS="${TEST_RELDIR//\//.}.${TEST_NAME}"
    TOTAL=$(( $TOTAL + 1 ))
    test_erred
}
test_timed_out() {
    junit_test "<error type=\"timeOut\" message=\"Timed out after $TEST_TIMEOUT\">$(safe4xml "$TEST_LOG")</error>"

    ERRORS=$(( $ERRORS + 1 ))
    header "${CLR_FAIL}TIMEOUT${CLR_NONE} with code $STATUS in ${TEST_TIME}s"

    finish "early due to TIMEOUT"
}

run_file() {
  local test_file="$1"
  local test_silent="${2:false}" # str([silent|anything_like_false])
  TEST_NAME="$(basename "$test_file")"
  TEST_CLASS="${TEST_RELDIR//\//.}.${TEST_NAME%.*}"

  TOTAL=$(( $TOTAL + 1 ))
  TEST_TIMEOUT=$(config $test_file timeout $DEFAULT_TIMEOUT)
  TEST_SKIP=$(config $test_file skip 0)

  header "Running"
  if [[ "$DRYRUN" = "1"  ]] || [[ $TEST_SKIP = "1" ]]; then
      echo "Only dry-run" > "$TEST_LOG"
      test_skipped
      return
  fi
  TEST_TIME_START="$(date "+%s")"
  chmod +x "$test_file"
  (timeout $TEST_TIMEOUT "$test_file" "$CONTROLLER1" "$CONTROLLER2" "$CONTROLLER3" < /dev/null) 2>&1 | tee "$TEST_LOG"
  STATUS=${PIPESTATUS[0]}
  TEST_TIME="$(( $(date "+%s") - $TEST_TIME_START ))"

  if [[ "$STATUS" = "$EXIT_SKIP" ]]; then
    test_skipped
  elif [[ "$STATUS" != "0" ]]; then
    if [[ "$STATUS" = "${EXIT_TIMEDOUT}" || "$STATUS" = "$EXIT_TIMEDKILL" ]]; then
        test_timed_out
    elif [[ "$STATUS" = "${EXIT_DIRTY}" ]]; then
        test_erred
    fi
    test_failed
  else
    test_passed
  fi
}

run_directory() {
    local runner_back_dir=$(pwd)

    if [[ -z "$TEST_RELDIR" ]]; then
        # first call with full path, not subfolder name
        export TEST_RELDIR="$1"
        export runner_back_reldir="$TEST_RELDIR"
    else
        export runner_back_reldir="$TEST_RELDIR"
        export TEST_RELDIR="$TEST_RELDIR/$(basename "$1")"
    fi

    cd "$1"
    local runner_current_dir=$(pwd)

    if [[ -f "./setup.sh" ]]; then
        if [[ "$DRYRUN" = "1" ]]; then
            echo "./setup.sh"
        else
            chmod +x ./setup.sh
            source ./setup.sh < /dev/null || setupteardown_failed setup $?
        fi
    fi

    while read test_file; do
        cd "${runner_current_dir}"
        run_file "$test_file"
        cd "${runner_current_dir}"
    done < <(find . -maxdepth 1 -type f -name \*.sh \! -name setup.sh \! -name teardown.sh | sort)

    while read subdir; do
        run_directory "$subdir"
    done < <(find . -maxdepth 1 -type d|grep -v '^\.$' | sort)

    if [[ -f "./teardown.sh" ]]; then
        if [[ "$DRYRUN" = "1" ]]; then
            echo "./teardown.sh"
        else
            chmod +x ./teardown.sh
            source ./teardown.sh < /dev/null || setupteardown_failed teardown $?
        fi
    fi

    export TEST_RELDIR="$runner_back_reldir"
    cd "$runner_back_dir"
}

run_directory "$TESTS_DIR"

finish
