.. _phpt_file_structure:

The ``.phpt`` file structure
============================

Now that we know how to run the tests with run-tests, let's dive into a phpt file in more detail. A phpt file is just a
normal PHP file but it contains a number of different sections which run-tests supports.

A basic test example
--------------------

Here's a basic example of a PHP source test that tests the ``echo`` construct.

.. literalinclude:: echo_basic.phpt
   :language: php

Did you know that `echo can take a list of arguments`_? Well you do now.

There are `many more sections`_ that are available to us in a phpt file, but these three are the bare-minimum required.
The ``--EXPECT--`` section has a few variations but we'll get into describing the sections in just a bit.

Notice that of the three sections, we have everything we need to run a black-box test. We have a name for the test, a
bit of code and the expected output. Again, black-box testing doesn't care *how* the code runs, it only concerns itself
with the end result.

.. _echo can take a list of arguments: http://php.net/manual/en/function.echo.php
.. _many more sections: http://qa.php.net/phpt_details.php

Some notable sections
---------------------

Now that we've seen the three required sections for every  ``.phpt`` file let's take a look a few other common sections
we'll no doubt encounter.

``--TEST--`` : The name of the test
    The `--TEST-- section`_ just describes the test (for humans) in one line. This will be displayed in the console when
    the test is run, so it's good to be descriptive but not overly verbose. If your test needs a longer description, add
    a `--DESCRIPTION-- section`_.
    
    .. code-block:: php
    
        --TEST--
        json_decode() with large integers

    .. note:: The ``--TEST--`` section must be the very first line of the phpt file. Otherwise run-tests will not
              consider it to be a valid test file and mark the test as "borked".

``--FILE--`` : The PHP code to run
    The `--FILE-- section`_ is the PHP code that we want to test. In our above example we're making sure the ``echo``
    construct can take a list of arguments and concatenate them into standard out.

    .. code-block:: php
    
        --FILE--
        <?php
        $json = '{"largenum":123456789012345678901234567890}';
        $x = json_decode($json);
        var_dump($x->largenum);
        $x = json_decode($json, false, 512, JSON_BIGINT_AS_STRING);
        var_dump($x->largenum);
        echo "Done\n";
        ?>

    .. note:: Although it is considered a best-practice to leave off the closing PHP tag (``?>``) in userland, this is
              not the case with a phpt file. If you leave off the closing PHP tag, run-tests will have no trouble
              running your test, but your test will no longer be able to run as a normal PHP file. It will also make
              your IDE go bonkers. So always remember to include the closing PHP tag in every ``--FILE--`` section.

``--EXPECT--`` : The expected output
    The `--EXPECT-- section`_ contains exactly what we would expect to see from standard output. If you're expecting
    fancy assertions like you get in `PHPUnit`_, you won't get any here. Remember, these are *`functional tests`_* so we
    just examine the output after providing inputs.
    
    .. code-block:: php
    
        --EXPECT--
        float(1.2345678901235E+29)
        string(30) "123456789012345678901234567890"
        Done

    .. note:: Trailing new lines are trimmed off by run-tests for both the expected and actual output so you don't have
              to worry about adding or removing trailing new lines at the end of the ``--EXPECT--`` section.

``--EXPECTF--`` : The expected output with substitution
    Because the tests need to run on a multitude of environments, we often times may not know what the actual output
    of a script will be. Or perhaps the functionality that your testing is nondeterministic. For this use case we have
    the `--EXPECTF-- section`_ which allows us to substitute sections of output with substitution characters much
    like the `sprintf() function`_ in PHP.
    
    .. code-block:: php
    
        --EXPECTF--
        string(%d) "%s"
        Done
    
    This is particularly handy when creating error-case tests that output the absolute path to the PHP file; something
    that would vary from environment to environment.
    
    Below is an abbreviated error-case example taken from `a real test`_ of the `password hashing functions`_ which
    makes use of the ``--EXPECTF--`` section.
    
    .. code-block:: php
    
        --TEST--
        Test error operation of password_hash() with bcrypt hashing
        --FILE--
        <?php
        var_dump(password_hash("foo", PASSWORD_BCRYPT, array("cost" => 3)));
        ?>
        --EXPECTF--
        Warning: password_hash(): Invalid bcrypt cost parameter specified: 3 in %s on line %d
        NULL

``--SKIPIF--`` : Conditions that a test should be skipped
    Since PHP can be configured with myriad options, the build of PHP that you're running might not be compiled with the
    required dependencies that are needed to run a test. The case where this is most common is the extension tests.
    
    If a test needs an extension installed in order to run the test will have a `--SKIPIF-- section`_ which checks that
    the extension is indeed installed.
    
    .. code-block:: php
    
        --SKIPIF--
        <?php if (!extension_loaded('json')) die('skip ext/json must be installed'); ?>
    
    Any tests that meet the ``--SKIPIF--`` condition will be marked as "skipped" by run-tests and continue on to the
    next test in the queue. Any text after the word "skip" will be returned in the output when you run the test from
    run-tests as the reason why the test was skipped.
    
    Many of the tests will halt the script execution with `die()`_ or `exit()`_ if the ``--SKIPIF--`` condition is met
    as in the example above. It is important to understand that just because you ``die()`` in a ``--SKIPIF--`` section,
    that does not mean run-tests will skip your test. Run-tests simply examines the output of ``--SKIPIF--`` and looks
    for the word "skip" as the first four characters. If the first word is not "skip", the test will not be skipped.
    
    In fact, you don't have to halt execution at all as long as "skip" is the first word of the output.
    
    The following example will skip a test. Note how we didn't halt the script execution.
    
    .. code-block:: php
    
        --SKIPIF--
        <?php if (!extension_loaded('json')) echo 'skip'; ?>
    
    By contrast, examine the following example. Notice how it halts script execution but since the word "skip" isn't the
    the first word in the output, run-tests will still happily run the test without skipping it.
    
    .. code-block:: php
    
        --SKIPIF--
        <?php if (!extension_loaded('json')) exit; ?>
    
    .. note:: Although it is not required to halt script execution in the ``--SKIPIF--`` section, it is always highly
              recommended so that you can still run the phpt file as a normal php file and see a nice message like "skip
              ext/json must be installed" instead of getting a ton of random errors.

``--INI--``
    Sometimes tests rely on having very specific INI settings set. In this case you can define any INI settings with the
    `--INI-- section`_. Each INI setting is placed on a new line within the section.
    
    .. code-block:: php
    
        --INI--
        date.timezone=America/Chicago
    
    Run-tests does all the magic involved with setting the INI configuration for you.

.. _--TEST-- section: http://qa.php.net/phpt_details.php#test_section
.. _--DESCRIPTION-- section: http://qa.php.net/phpt_details.php#description_section
.. _--FILE-- section: http://qa.php.net/phpt_details.php#file_section
.. _--EXPECT-- section: http://qa.php.net/phpt_details.php#expect_section
.. _PHPUnit: https://phpunit.de/
.. _functional tests: https://en.wikipedia.org/wiki/Functional_testing
.. _--EXPECTF-- section: http://qa.php.net/phpt_details.php#expectf_section
.. _sprintf() function: http://php.net/sprintf
.. _a real test: https://github.com/php/php-src/blob/master/ext/standard/tests/password/password_bcrypt_errors.phpt
.. _password hashing functions: http://php.net/password
.. _--SKIPIF-- section: http://qa.php.net/phpt_details.php#skipif_section
.. _die(): http://php.net/die
.. _exit(): http://php.net/exit
.. _--INI-- section: http://qa.php.net/phpt_details.php#ini_section

Writing a simple test
---------------------

Let's write our first test just to get familiar with the process.

Typically tests are stored in a ``tests/`` directory that lives near the code we want to test. For example, the `PDO
extension`_ is found at ``ext/pdo`` in the PHP source code. If you open that directory, you'll see a `tests/ directory`_
with lots of ``.phpt`` files in it. All the other extensions are set up the same way. There are also tests for the Zend
engine which are located in `Zend/tests/`_.

For this example, we'll just temporarily create a test in the root ``php-src`` directory. Create and open a new file
with your favorite editor.

.. code-block:: bash

    $ vi echo_basic.phpt

.. note:: If you've never used vim before, you'll probably be stuck after running the command above. Just press
          ``<esc>`` a bunch of times and then type ``:q!`` and it should poop you back out to the terminal. You can just
          use your favorite editor for this part instead of vim. And then when you get an extra second later on, `learn
          vim`_.

Now copy and paste the example test from above into the new test file. Here's the test file again to save you some
scrolling around.

.. literalinclude:: echo_basic.phpt
   :language: php

After you save the file as ``echo_basic.phpt`` in the root of the PHP source code and exit your editor, run the example
test with make.

.. code-block:: bash

    $ make test TESTS=echo_basic.phpt

If everything worked, you'll see the following passing test summary.

.. code-block:: bash

    =====================================================================
    Running selected tests.
    PASS echo - basic test for echo language construct [echo_basic.phpt]
    =====================================================================
    Number of tests :    1                 1
    Tests skipped   :    0 (  0.0%) --------
    Tests warned    :    0 (  0.0%) (  0.0%)
    Tests failed    :    0 (  0.0%) (  0.0%)
    Expected fail   :    0 (  0.0%) (  0.0%)
    Tests passed    :    1 (100.0%) (100.0%)
    ---------------------------------------------------------------------
    Time taken      :    0 seconds
    =====================================================================

Notice how text from the ``--TEST--`` section of the test is being displayed in the console:

.. code-block:: bash

    PASS echo - basic test for echo language construct [echo_basic.phpt]

To illustrate the point that black-box testing only cares about the output, let's change the PHP code in the
``--FILE--`` section and keep everything else the same.

.. code-block:: php

    <?php
    const BANG = '!';
    class works {}
    echo sprintf('This %s and takes args%s', works::class, BANG);
    ?>

Now let's run the test again.

.. code-block:: bash

    $ make test TESTS=echo_basic.phpt

The test should still pass because the expected output is still the same as it was before. Let's try another example.
Replace the PHP code in the ``--FILE--`` section of the test with the following code and then run the test again.

.. code-block:: php

    <?php
    $url = 'https://gist.githubusercontent.com/SammyK/9c7bf6acdc5bcaa2cfbb404adc61abe6/';
    $url .= 'raw/04af30473fc78033f7d8941ecd567934b0f804c0/foo-phpt-output.txt';
    echo file_get_contents($url);
    ?>

Although this one looks obscure, I set up a `Gist with the expected output`_ and we're just dumping the body of an HTTP
request to that Gist. Unless there are network connection issues or if the gist gets deleted, this will produce the same
output as the other bits of code and the test will still pass. This will fail if you don't have the `ext/openssl`_
extension installed since the Gist is behind https.

Let's try one more example. Replace the PHP code in the ``--FILE--`` section with the following.

.. code-block:: php

    <?php
    ob_start();

    echo 'and ';
    sleep(1);
    echo 'takes ';
    sleep(1);
    echo 'args!';

    $foo = ob_get_contents();
    ob_clean();

    echo 'This works ';
    sleep(1);
    echo $foo;
    ?>

Crazy, right? This will take a few seconds just to output a simple string and you'd never do this in real life, but the
test will still pass. Run-tests does not care that that your code is slow [#]_ or inefficient or just terrible, if the
expected output matches the actual output, your test will be in the green.

.. _PDO extension: http://php.net/pdo
.. _tests/ directory: https://github.com/php/php-src/tree/master/ext/pdo/tests
.. _Zend/tests/: https://github.com/php/php-src/tree/master/Zend/tests
.. _learn vim: https://www.google.com/search?q=learn+vim
.. _Gist with the expected output: https://gist.githubusercontent.com/SammyK/9c7bf6acdc5bcaa2cfbb404adc61abe6/raw/04af30473fc78033f7d8941ecd567934b0f804c0/foo-phpt-output.txt
.. _ext/openssl: http://php.net/openssl
.. [#] **Timeouts:** The default timeout for run-tests is 60 seconds (or 300 seconds when testing for memory leaks) but you can specify a different timeout using the ``--set-timeout`` flag.
