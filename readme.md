# Re-sign IPA

__DEPRECATED!__
Will be removed by: 2017.10.01
Please use [export-xcarchive](https://github.com/bitrise-steplib/steps-export-xcarchive) step instead.

Re-sign the selected IPA with new Certificate and Provisioning Profile.

## How to use this Step

Can be run directly with the [bitrise CLI](https://github.com/bitrise-io/bitrise),
just `git clone` this repository, `cd` into it's folder in your Terminal/Command Line
and call `bitrise run test`.

*Check the `bitrise.yml` file for required inputs which have to be
added to your `.bitrise.secrets.yml` file!*

## Run the tests in Docker, with `docker-compose`

You can call `docker-compose run --rm app bitrise run test` to run the test
inside the Bitrise Android Docker image.
