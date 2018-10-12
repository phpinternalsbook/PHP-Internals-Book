.. _overview:

Testing overview
================

PHP has an extensive test suite with over 15,000 individual test files. The test files are run with PHP's black-box
testing tool called `run-tests.php`_ which can be found in the root directory of the php source code.

"But wait!" you say, "I heard that PHP source doesn't have any unit tests." You are correct. The PHP source code has
zero unit tests. But it does have `functional tests`_ and lucky for us, these particular functional tests are written in
PHP. The test files have a ``.phpt`` file extension and can be run just like any normal PHP file.

The official documentation for writing phpt tests lives at `qa.php.net`_.

.. _run-tests.php: https://github.com/php/php-src/blob/master/run-tests.php
.. _`functional tests`: https://en.wikipedia.org/wiki/Functional_testing
.. _`qa.php.net`: http://qa.php.net/write-test.php

Black-box testing
-----------------

In a nutshell, `black-box testing`_ sends input to some function and examines the output after the function has finished
execution. If the output matches what we were expecting, then the test has passed. Black-box testing doesn't care *how*
something is done, it only cares about the end result. This is exactly how ``run-tests.php`` works; it takes a set of
inputs, runs some PHP code and then examines the output. If the output matches what is expected, then the test passes.

.. _black-box testing: https://en.wikipedia.org/wiki/Black-box_testing

Where the test files live
-------------------------

The test files live in several different places throughout the codebase in folders named ``tests``. Each test folder
contains ``.phpt`` files pertaining to its containing folder's code.

* ``ext/{extension-name}/tests/`` Extension tests
* ``sapi/{sapi-name}/tests/`` SAPI tests
* ``Zend/tests/`` Zend engine tests
* ``tests/`` More Zend engine tests
