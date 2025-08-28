Testing
=======

PDO has a set of "core" tests that all drivers should pass before being
released.  They're designed to run from the PHP source distribution, so
running the tests for your driver requires moving things around a bit.
The suggested procedure is to obtain the latest PHP 5.1 snapshot and
perform the following step:

.. code-block:: bash

    $ cp -r pdo_SKEL /path/to/php-5.1/ext

This will allow the test harness to run your tests.  The next thing you
need to do is create a test that will redirect into the PDO common core tests.
The convention is to name this file ``common.phpt``; it
should be placed in the tests subdirectory that was created by
``ext_skel`` when you created your extension skeleton.
The content of this file should look something like the following:

.. code-block:: php

    --TEST--
    SKEL
    --SKIPIF--
    <?php
    if (!extension_loaded('pdo_SKEL')) print 'skip';
    ?>
    --REDIRECTTEST--
    if (false !== getenv('PDO_SKEL_TEST_DSN')) {
        # user set them from their shell
        $config['ENV']['PDOTEST_DSN'] = getenv('PDO_SKEL_TEST_DSN');
        $config['ENV']['PDOTEST_USER'] = getenv('PDO_SKEL_TEST_USER');
        $config['ENV']['PDOTEST_PASS'] = getenv('PDO_SKEL_TEST_PASS');
        if (false !== getenv('PDO_SKEL_TEST_ATTR')) {
            $config['ENV']['PDOTEST_ATTR'] = getenv('PDO_SKEL_TEST_ATTR');
        }
        return $config;
    }
    return array(
        'ENV' => array(
            'PDOTEST_DSN' => 'SKEL:dsn',
            'PDOTEST_USER' => 'username',
            'PDOTEST_PASS' => 'password'
        ),
        'TESTS' => 'ext/pdo/tests'
    );

This will cause the common core tests to be run, passing the values of
``PDOTEST_DSN``, ``PDOTEST_USER`` and
``PDOTEST_PASS`` to the PDO constructor as the
``dsn``, ``username`` and
``password`` parameters.  It will first check the environment, so
that appropriate values can be passed in when the test harness is run,
rather than hard-coding the database credentials into the test file.

The test harness can be invoked as follows:

.. code-block:: bash

    $ cd /path/to/php-5.1
    $ make TESTS=ext/pdo_SKEL/tests PDO_SKEL_TEST_DSN="skel:dsn" \
      PDO_SKEL_TEST_USER=user PDO_SKEL_TEST_PASS=pass test
