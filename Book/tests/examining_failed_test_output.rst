.. _examining_failed_test_output:

Examining failed test output
============================

We've learned how to create and run tests and have had great success with passing tests, but what happens when things go
wrong? We'll examine how to help ourselves debug failed tests using the failed-test output files.

Failed test output files
------------------------

If a test would fail, the test results will be dumped in the directory where the test file resides. This happens for
each failed test. For example for a failed test ``001.phpt`` you will get this output:

* ``001.log`` The output of this one test
* ``001.exp`` The expected test result
* ``001.out`` The actual test result
* ``001.diff`` The difference between the expected and actual result
* ``001.php`` A PHP snippet that contains the code of the failed test
* ``001.sh`` A script to run the PHP snippet of the failed test

With all this information at hand, you can start debugging your code.
