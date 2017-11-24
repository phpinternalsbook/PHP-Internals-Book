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

The ``.sh`` bash script is a wrapper around the failed php script that makes it easy to re-run the failed script with
the same runtime conditions as the test run. With all this information at hand, you can start debugging your code.

Examine failed test output inline
---------------------------------

Having all these files on your filesystem is not always convenient. Sometimes you might just want to see the failed
test output on your screen, inline with the failed test. The ``run-tests.php`` script accepts flags to enable such
behavior ``--show-[all|php|exp|diff|out]``. For example if you want to see the diffs inline:

    .. code-block:: bash

        ./run-tests.php --show-diff
        ...
        TEST 613/14433 [tests/lang/operators/nan-comparison-false.phpt]
        ========DIFF========
        002+ bool(true)
        003+ bool(true)
        004+ bool(true)
        005+ bool(true)
        002- bool(false)
        003- bool(false)
        004- bool(false)
        005- bool(false)
        ========DONE========
        ...

In case of diff they are only printed if there is an actual difference. There are also flags to print the skip
criteria or the clean scripts ``--show-[skip|clean]``. For example:

    .. code-block:: bash

        ./run-tests.php --show-clean
        ...
        PASS Test for buffering in core functions with implicit flush on [tests/func/009.phpt]
        TEST 399/14433 [tests/func/010.phpt]
        ========CLEAN========
        <?php
        @unlink(dirname(__FILE__).'/010-file.php');
        ?>
        ========DONE========
        PASS function with many parameters [tests/func/010.phpt]
        PASS Test bitwise AND, OR, XOR, NOT and logical NOT in INI via error_reporting [tests/func/011.phpt]
        ...

There even is a flag to show slow tests ``--show-slow`` that accepts a number of milliseconds. At the end of the test
run, the tests that ran slower are reported. Say you want to inspect tests in ``ext/standard/tests/file`` that run
more than 10 seconds:

    .. code-block:: bash

        ./run-tests.php --show-slow 10000 ext/standard/tests/file
        =====================================================================
        SLOW TEST SUMMARY
        ---------------------------------------------------------------------
        (28.043 s) Test fileatime(), filemtime(), filectime() & touch() functions : usage variation [ext/standard/tests/file/005_variation.phpt]
        =====================================================================

Unfortunately the make script does not have environment variables to activate these flags. But you can use them anyway
by abusing the ``TESTS`` variable instead:

    .. code-block:: bash

        make test TESTS=--show-all
