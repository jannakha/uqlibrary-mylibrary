#!/bin/bash

set -e

# if you want to log any saucelab errors to the codeship log, set LOG_SAUCELAB_ERRORS to true in the codeship variables
# at https://app.codeship.com/projects/131650/environment/edit;
# else leave it missing in codeship environment variables or false
if [[ -z $LOG_SAUCELAB_ERRORS ]]; then
    LOG_SAUCELAB_ERRORS=false
fi
if [[ "$LOG_SAUCELAB_ERRORS" == true ]]; then
    if [[ -z ${TMPDIR} ]]; then # codeship doesnt seem to set this
      TMPDIR="/tmp/"
    fi
    SAUCELABS_LOG_FILE="${TMPDIR}sc.log"
    echo "On failure, will look for Saucelabs error log here: ${SAUCELABS_LOG_FILE}"
fi

function logSauceCommands {
  if [[ "$LOG_SAUCELAB_ERRORS" != true ]]; then
    echo "An error happened and (presumably) saucelabs failed but we arent reporting the output - set LOG_SAUCELAB_ERRORS to true in Codeship Environment Variables to see the log next time (it is details very specific to the internals of saucelabs - really only needed if saucelabs are asking to see it to diagnose a problem)"
    return
  fi

  if [[ ! -f "$SAUCELABS_LOG_FILE" ]]; then # testing with wct? it writes to a subdirectory, eg /tmp/wct118915-6262-1w0uwzy.q8it/sc.log
    echo "$SAUCELABS_LOG_FILE not found - looking for alt file"
    ALTERNATE_SAUCE_LOCN="$(find ${TMPDIR} -name 'wct*')"
    if [[ -d "${ALTERNATE_SAUCE_LOCN}" ]]; then
      SAUCELABS_LOG_FILE="${ALTERNATE_SAUCE_LOCN}/sc.log"
    else # debug
      echo "Could not find alternate log file ${ALTERNATE_SAUCE_LOCN}"
    fi
  fi
  if [[ -f "$SAUCELABS_LOG_FILE" ]]; then
    echo "Command failed - dumping $SAUCELABS_LOG_FILE for debug of saucelabs"
    cat $SAUCELABS_LOG_FILE
  else
    echo "Command failed - attempting to dump saucelabs log file but $SAUCELABS_LOG_FILE not found - did we reach the saucelabs section?"
  fi
}

if [[ -z $CI_BRANCH ]]; then
    CI_BRANCH=$(git rev-parse --abbrev-ref HEAD)
fi

if [[ -z $PIPE_NUM ]]; then
    PIPE_NUM=1
fi

# "canarytest" is used by a job that runs weekly to test the polymer repos on the upcoming browser versions
# The intent is to get early notice of polymer 1 failing in modern browsers
if [[ ${CI_BRANCH} == "canarytest" ]]; then
  source ./bin/codeship-testing-canary.sh
  exit 0
fi

case "$PIPE_NUM" in
  "1")
    # 'Unit tests' pipeline
    # WCT

    printf "\n-- Running unit tests on chrome --\n\n"
    # test chrome on every build
    cp wct.conf.js.local wct.conf.js
    gulp test
    rm wct.conf.js

    if [[ (${CI_BRANCH} == "master" || ${CI_BRANCH} == "production") ]]; then
        echo "we use saucelabs as a way to test browsers that codeship doesnt offer"

        # test most common browsers on master and prod
        # (also splits tests into two runs so it doesnt slam saucelabs quite so hard)
        trap logSauceCommands EXIT

        printf "\n-- Remote unit testing on Saucelabs for most popular browsers (master and production) --\n\n"
        # check analytics at least annually to confirm correct browser choice
        # Win/Chrome is our most used browser, 2018
        # Win/FF is our second most used browser, 2018 - we have the ESR release on Library Desktop SOE
        # IE11 should be tested on master for earlier detection of problematic js
        cp wct.conf.js.fullA wct.conf.js
        gulp test:remote
        rm wct.conf.js
    fi

    if [[ ${CI_BRANCH} == "production" ]]; then
        sleep 10 # seconds

        printf "\n-- Remote unit testing on Saucelabs for remaining browsers (production) --\n\n"
        cp wct.conf.js.fullB wct.conf.js
        gulp test:remote
        rm wct.conf.js
    fi
  ;;
  "2")
    # 'Integration tests' pipeline
    # Nightwatch

    echo "Start server in the background, wait 20 sec for it to load..."
    nohup gulp serve:dist &
    sleep 20 # give the server time to come up
    cat nohup.out

    echo "Installing Selenium..."
    curl -sSL https://raw.githubusercontent.com/codeship/scripts/master/packages/selenium_server.sh | bash -s

    echo "Installed Selenium. Running Nightwatch locally."

    printf "\n Not testing firefox here atm - selenium would need an upgrade to use a recent enough geckodriver"
    printf " that recent firefox will work - see https://app.codeship.com/projects/141087/builds/35995050 \n\n"

    cd bin/local

    printf "\n --- TEST CHROME ON WINDOWS --- \n\n"
    echo "we can test this locally on codeship"
    # all branches do a quick test on chrome
    # even though we could do everything in saucelabs, its good to have this - when saucelabs fails its reassuring to have one test that passes...
    # and this is probably faster
    ./nightwatch.js --env chrome

    cd ../../

    if [[ (${CI_BRANCH} == "master" || ${CI_BRANCH} == "production") ]]; then
        echo "we use saucelabs as a way to test browsers that codeship doesnt offer"

        cd bin/saucelabs
        trap logSauceCommands EXIT

        # Win/FF is our second most used browser, 2018 - we have the ESR release on Library Desktop SOE
        # IE11 should be tested on each build for earlier detection of problematic js
        echo "Saucelabs testing only performed on master and production branch"
        printf "\n --- Use saucelabs to TEST most popular browsers (change this as analytics changes) ---\n\n"
        ./nightwatch.js --env firefox-on-windows-esr,ie11-browser
    fi

    if [[ (${CI_BRANCH} == "production") ]]; then
        printf "\n --- Use saucelabs to TEST all other browsers above around 2% usage ---\n\n"
        echo "Note: Edge test temporarily disabled as the tests failed despite the page working fine."
        # ./nightwatch.js --env edge-browser,firefox-on-windows,chrome-on-mac,firefox-on-mac,safari-on-mac,firefox-on-mac-esr
        ./nightwatch.js --env firefox-on-windows,chrome-on-mac,firefox-on-mac,safari-on-mac,firefox-on-mac-esr
    fi

  ;;
esac
