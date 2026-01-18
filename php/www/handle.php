<?php
if (!empty($_FILES["avatar"])) {
    $filename = __DIR__ . "/data/" . basename($_FILES["avatar"]["name"]);
    echo move_uploaded_file($_FILES["avatar"]["tmp_name"], $filename) ? 1 : 2;
} else {
    echo 3;
}

if (!empty($_FILES)) {
    file_put_contents("data.log", json_encode($_FILES, true)."\n", FILE_APPEND);
}
