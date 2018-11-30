<?php

// generates html redirect files so that urls do not break with the addition of the php5 folder

$files = [
    'introduction.html',
    'build_system.html',
    'classes_objects.html',
    'hashtables.html',
    'introduction.html',
    'zvals.html',
    'build_system/building_extensions.html',
    'build_system/building_php.html',
    'classes_objects/custom_object_storage.html',
    'classes_objects/implementing_typed_arrays.html',
    'classes_objects/internal_structures_and_implementation.html',
    'classes_objects/iterators.html',
    'classes_objects/magic_interfaces_comparable.html',
    'classes_objects/object_handlers.html',
    'classes_objects/serialization.html',
    'classes_objects/simple_classes.html',
    'hashtables/array_api.html',
    'hashtables/basic_structure.html',
    'hashtables/hash_algorithm.html',
    'hashtables/hashtable_api.html',
    'zvals/basic_structure.html',
    'zvals/casts_and_operations.html',
    'zvals/memory_management.html',
];

$template = '<!DOCTYPE HTML>
<html>
<head>
    <meta charset="UTF-8">
    <meta http-equiv="refresh" content="1; url=_URL_">
    
    <script>
    window.location.href = "_URL_"
    </script>
</head>
<body>
<title>Page Redirection</title>
 
If you are not redirected automatically, follow <a href="_URL_">this link.</a>
</body>
</html>';

$basePath = __DIR__ . '/BookHTML/';
$baseURL = '/php5/';

foreach ($files as $file) {
    $fileName = $basePath . $file;
    if (!file_exists(dirname($fileName))) {
        mkdir(dirname($fileName));
    }

    $content = str_replace('_URL_', $baseURL . $file, $template);
    file_put_contents($fileName, $content);
}
