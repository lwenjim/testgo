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

function AppLogReportData(){
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
{"auth":{"token":{"user_id":1}},"cmd":1,"request_data":"CgQSAigBEMe3qP1B","response_data":"CgMIyAESFwgBEgQiIigp8gEMIjEyM0BxcS5jb20i"}
    ' -plaintext localhost:19091 rpc.NetSecurityDataReport.ReceiveReportData)
    echo $addResp  
}