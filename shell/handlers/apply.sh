#! /usr/bin/env bash
function GroupPublicApply() {
    domain=localhost:9090
    addResp=$(grpcurl -plaintext $domain rpc.Group.GetGroupChatCategorys)
    echo $addResp

    addResp=$(grpcurl -d '
       {
           "auth":{
               "token_raw":"",
               "token":{
                   "user_id":10043
               },
               "request_id":"xxx"
           },
           "category_id":1,
           "address":"abc",
           "description":"123456",
           "group_id":497,
           "latitude":"31.219648",
           "longitude":"121.443869",
           "title":"测试群1"
       }
       ' -plaintext $domain rpc.Group.ApplyPublicGroupChat)
    echo $addResp
    echo

    addResp=$(grpcurl -plaintext $domain rpc.Group.GetGroupChatPublicInfos)
    echo $addResp

    addResp=$(grpcurl -d '
    {
      "judge_status":2,
      "group_ids":[497],
      "reason":"abc" 
    }
    ' -plaintext $domain rpc.Group.AuditGroupChatPublicApply)
    echo $addResp

    addResp=$(grpcurl -d '
    {
      "group_id":497
    }
    ' -plaintext $domain rpc.Group.GetGroupChatPublicInfo)
    echo $addResp
}

function AppLogReportData() {
    addResp=$(grpcurl -d '
            {
                "auth": {
                    "token": {
                        "user_id": 1
                    }
                },
                "datas": [
                    {
                        "call_user_id": 1,
                        "to_user_id": 1,
                        "to_group_id": 1,
                        "chat_type": 1,
                        "os_type": "os-type",
                        "device_brand": "device-brand",
                        "device_model": "device-model",
                        "ping": 123,
                        "network_operator": 1,
                        "data": "eyJudW1iZXJfY2FsbHMiOjEwLCJoYW5ndXBfdHlwZSI6MiwicmVhc29uIjoiYWJjIiwibXNnX2lkIjoxLCJjYWxsX3RpbWUiOjEwfQ==",
                        "create_time": 123
                    },
                    {
                        "call_user_id": 2,
                        "to_user_id": 1,
                        "to_group_id": 1,
                        "chat_type": 1,
                        "os_type": "os-type",
                        "device_brand": "device-brand",
                        "device_model": "device-model",
                        "ping": 123,
                        "network_operator": 1,
                        "data": "eyJudW1iZXJfY2FsbHMiOjEwLCJoYW5ndXBfdHlwZSI6MiwicmVhc29uIjoiYWJjIiwibXNnX2lkIjoxLCJjYWxsX3RpbWUiOjEwfQ==",
                        "create_time": 123
                    }
                ]
            }
    ' -plaintext localhost:19093 rpc.Edge.AppLogReport)
    echo $addResp
}

function NetSecurityDataReport() {
    addResp=$(grpcurl -d '
    {
      "auth": {
        "token": {
          "user_id": 10019
        }
      },
      "cmd": 8,
      "request_data": "CgUSAyijThAg",
      "response_data": "CgMIyAE="
    }
    ' -plaintext localhost:19091 rpc.NetSecurityDataReport.ReceiveReportData)
    echo $addResp
}

function NetSecurityDataReport() {
    addResp=$(grpcurl -d '
    {
      "auth": {
        "token": {
          "user_id": 10019
        }
      },
      "cmd": 8,
      "request_data": "CgUSAyijThAg",
      "response_data": "CgMIyAE="
    }
    ' -plaintext localhost:19091 rpc.Upload.UploadFile)
    echo $addResp
}

function ss111(){
    addResp=$(grpcurl -d '
    {
      "auth": {
        "token": {
          "user_id": 22033
        }
      },
      "verify_token": "A1-I4Kwe2xTFbJ7ZmWED52JlQ4u7jsGyTomDtuzMBadaIVy81QYX6SclioA8Q_-imvAsEDhS8NY6w-fPY_LyTZRxWAa9H-ZAdVLBAU0ibbRvFr4c1tFZYHm2_JwhGF6saLIv6Vhq7w70oMuswTTBPsz91xH1iDJhDJStb3bC8p7eGSKFo6GqgzbsAY9YYukf-3CRIecP47ERTM4th5aZAIJ2gZzZrbYJhraDkgsGFe3KJx4UVtohFVo7JqaqJmsgz9Vyojnf8xMNiW188-edqvBx4vJWL1PVrUDjMqClZXActuc0thK8N_L-wYYsx6SxYPYMA3Oc_kwvONfM2raB_VlXw==",
      "channel": "1"
    }
    ' -H 'devid:8572' -H 'address:116.232.42.57' -plaintext authsv-svc:19090 rpc.Auth.OneClickLogin)
    echo $addResp
}

# 7837 android