Test() {
    echo 123
}

solitaire() {
    userQrcode=MAlHDK5Sg
    groupQrcode=O4W1DKcSg
    domain=https://devwww.jspp.com
    getinfoResp=$(curl --silent "$domain/solitaire/getinfo?user_qrcode=$userQrcode")
    echo $getinfoResp
    code=$(echo $getinfoResp | jq '.res')
    if [[ "$code" != "200" ]]; then
        echo "failed for /solitaire/getinfo"
        return
    fi

    addResp=$(curl --silent -d '
    {
        "title": "abc",
        "user_qrcode": "'$userQrcode'",
        "group_qrcode": "'$groupQrcode'",
        "content": [
        {
            "content": "abc"
        }
        ],
        "example": "abc",
        "extra_info": "abc"
    }' "$domain/solitaire/add")
    echo $addResp
    code=$(echo $addResp | jq '.res')
    if [[ "$code" != "200" ]]; then
        echo "failed for /solitaire/add"
        return
    fi
    topicQrcode=$(echo $addResp | jq '.data' | tr -d '"')

    detailResp=$(curl --silent "$domain/solitaire/detail?user_qrcode=$userQrcode&topic_qrcode=$topicQrcode")
    echo $detailResp
    code=$(echo $detailResp | jq '.res')
    if [[ "$code" != "200" ]]; then
        echo "failed for /solitaire/detail"
        return
    fi

    postResp=$(curl --silent -d '
    {
        "user_qrcode": "'$userQrcode'",
        "topic_qrcode": "'$topicQrcode'",
        "content": [
            {
                "content": "'$(uuidgen)'"
            }
        ]
    }' "$domain/solitaire/post")
    echo $postResp
    code=$(echo $postResp | jq '.res')
    if [[ "$code" != "200" ]]; then
        echo "failed for /solitaire/post"
        return
    fi
}

vote() {
    userQrcode=MAlHDK5Sg
    groupQrcode=O4W1DKcSg
    domain=https://devwww.jspp.com
    # domain=http://localhost:18083
    addResp=$(curl --silent -d '{
        "name": "'$(openssl rand -base64 8)'",
        "user_qrcode": "'$userQrcode'",
        "group_qrcode": "'$groupQrcode'",
        "end_time": '$(date -v+5d +"%s")',
        "is_multi_select": true,
        "is_anonymous": true,
        "option": [
        {
            "name": "中国队",
            "image": "https://img.jspp.com/xxx/xxx.png"
        },
        {
            "name": "美国队",
            "image": "https://img.jspp.com/xxx/xxx222.png"
        }
        ]
    }' $domain/vote/add)
    echo $addResp
    code=$(echo $addResp | jq '.res')
    if [[ "$code" != "200" ]]; then
        echo "failed for /vote/add"
        return
    fi
    topicQrcode=$(echo $addResp | jq '.data' | tr -d '"')

    listResp=$(curl -d '{"user_qrcode":"'$userQrcode'","group_qrcode":"'$groupQrcode'"}' --silent $domain/vote/list)
    echo $listResp
    code=$(echo $listResp | jq '.res')
    if [[ "$code" != "200" ]]; then
        echo "failed for /vote/list"
        return
    fi

    recordResp=$(curl --silent -d '
        {
            "user_qrcode": "'$userQrcode'",
            "topic_qrcode": "'$topicQrcode'"
        }' "$domain/vote/record")
    echo $recordResp
    code=$(echo $recordResp | jq '.res')
    if [[ "$code" != "200" ]]; then
        echo "failed for /vote/record"
        return
    fi

    postResp=$(curl --silent -d '
    {
        "user_qrcode": "'$userQrcode'",
        "topic_qrcode": "'$topicQrcode'",
        "option_id": [
        '$(echo $recordResp | jq ".data.options.[0].option.id")'
        ]
    }' "$domain/vote/post")
    echo $postResp
    code=$(echo $postResp | jq '.res')
    if [[ "$code" != "200" ]]; then
        echo "failed for /vote/post"
        return
    fi
}

insert1000000t_push() {
    num=0
    mysql -uroot -P3306 -p123456789 -h127.0.0.1 jspp -e 'TRUNCATE t_push'
    for _ in $(seq 1 100); do
        num=$((num + 1))
        echo 'insert into t_push(id, app_id, device_id, device_token,channel_type, ringtone_sound, text_message_sound) values (null, 0, ' $num ', "b44aba24fbcc24e07af700314eb41438f43424895a916f9a9e7d8b818905684f", 1, null, null)' >/tmp/t_push_test.sql
        for item in $(seq 1 10000); do
            num=$((num + 1))
            echo ',(null, 0, '$num', "b44aba24fbcc24e07af700314eb41438f43424895a916f9a9e7d8b818905684f", 1, null, null)' >>/tmp/t_push_test.sql
        done
        mysql -uroot -P3306 -p123456789 -h127.0.0.1 jspp -e 'source /tmp/t_push_test.sql'
    done
}

insert1000avatar() {
    for item in $(mysql 2>/dev/null -uroot -P3306 -p123456789 -h127.0.0.1 jspp -e 'select id, avatar from t_user limit 150'); do
        echo mysql -uroot -P3306 -p123456789 -h127.0.0.1 jspp -e 'insert into t_user_examine_name_avatar(user_id, user_name, avatar, event_id) values('${item}', "jspp'${item}'", "/6b120d/image/6b120d9ea5250c8bf854953db017153586e896fe-1080x1920", '${item}')'
    done
}
