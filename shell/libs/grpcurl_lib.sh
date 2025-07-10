GroupPublicApply() {
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

function GetMemberPermission() {
  addResp=$(grpcurl -d '
    {
      "auth": {
        "token": {
          "user_id": 22033
        }
      },
      "member_group_type":1
    }
    ' -H 'devid:8572' -H 'address:116.232.42.57' -plaintext squaresv-svc:9090 rpc.Square.GetMemberPermission)
  echo $addResp
}

function QueryWishPayStatus() {
  addResp=$(grpcurl -d '
    {
      "auth": {
        "token": {
          "user_id": 23555
        }
      }
    }
    ' -plaintext squaresv-svc:9090 rpc.Square.QueryWishPayStatus)
  echo $addResp
}

# map[member_group_type:2 order_no:1915586335352029184 user_id:23509 wish_member_type:2]
function UpdateWishMemberStatus() {
  addResp=$(grpcurl -d '
    {
      "auth": {
        "token": {
          "user_id": 23509
        }
      },
      "user_id":23509,
      "wish_member_type":2,
      "order_no":"1915586335352029184",
      "member_group_type":2
    }
    ' -plaintext squaresv-svc:19090 rpc.Square.UpdateWishMemberStatus)
  echo $addResp
}

# add_type:2 auth:map[request_id:U3PzL81HRz token:map[country_code:86 device_id:1199 device_type:1 expires:201811621529 user_id:23504] token_raw:***
function ApplyFriend() {
  addResp=$(grpcurl -d '
    {
      "auth": {
        "token": {
          "user_id": 23551
        }
      },
      "add_type":2,
      "user_id":10012
    }
    ' -plaintext usersv-svc:19091 rpc.User.ApplyFriend)
  echo $addResp
}


# 7837 android
# squaresv-svc:9090/rpc.Square/GetMemberPermission

function SetGroupAdmin() {
  addResp=$(grpcurl -d '
    {
      "auth": {
        "token": {
          "user_id": 10088
        }
      },
      "group_id":1064,
      "user_id":[23631,10023,10028,12888,22013]
    }
    ' -plaintext groupsv-svc:9090 rpc.Group.SetGroupAdmin)
  echo $addResp
}

function GetPermissionLimit () {
  addResp=$(grpcurl -d '
    {
      "auth": {
        "token": {
          "user_id": 10088
        }
      },
      "member_max_limit_type": 16
    }
    ' -plaintext squaresv-svc:9090 rpc.Square.GetPermissionLimit)
  echo $addResp
}


function EditUserInfo() {
  addResp=$(grpcurl -d '
    {
      "auth": {
        "token": {
          "user_id": 10043
        }
      },
      "info": {
        "card": {}
      }
    }
    ' -plaintext usersv-svc:9090 rpc.User.EditUserInfo 2>&1)
  echo $addResp
}
