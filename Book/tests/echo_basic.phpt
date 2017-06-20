--TEST--
echo - basic test for echo language construct
--FILE--
<?php
echo 'This works ', 'and takes args!';
?>
--EXPECT--
This works and takes args!