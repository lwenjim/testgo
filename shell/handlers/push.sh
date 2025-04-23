function PushMsg(){
    curl \
    -H "Content-Type: application/json" \
    -H "push-type: 0" \
    -H "Authorization: Bearer eyJraWQiOiJkMjA1Zjg3ZTgzOTQ0ZjU1YWExNDJiMTczNmZmNzQ3MyIsInR5cCI6IkpXVCIsImFsZyI6IlBTMjU2In0.eyJhdWQiOiJodHRwczovL29hdXRoLWxvZ2luLmNsb3VkLmh1YXdlaS5jb20vb2F1dGgyL3YzL3Rva2VuIiwiaXNzIjoiMTEzNjk2NTY5IiwiZXhwIjoxNzQzMDQyNTg2LCJpYXQiOjE3NDI0Mzc3ODZ9.OSeVrbFvtJ6gUfeO8yJrfFTd8wSTQYv5ODoQTzT7gwOpEMj3Ae_NhZSdeYN8U6pmRN2BNPS1Dlpyd1naWDAmRyLqReYa3lPWrfQVMcLFlPks6c94FTwn_lqTUvu81TckZDDr2kpiVT878kslyOCDMjpcKtWTQOzxJrDtxb6O12xNqLN9QRw33uZrFOtOBotj19BEGzI6V6LtFNoNWNsTV5ISp2kH5TYQko6hGCsVj9BD-0hRGLeVkRL8eIV8SG7OHYIkTnwLYoxUxxqw1H76ra-6uqmBt8gLgaA08yH3MyWx8RN4iU2LhRR5wzRp9eVcLHDOgj-Yu2Pjvcw6NP9hKPVTWUyVzyhw1pA7YCqQbih3Nz4nH2CPbyIYE6RNWgTbxbJbshdy4Za_OVNdi3TmTSqBW0jYjAeicJisEq06cQLPGqeeMIWaE-JK9LGhglV0b3ZT6SpMhjQ1yIGro659ga72nbgTPneiu7iwhOdCjKtPsvdO3DgPYiyOAJJr61eNNUAPo6d0afAW6cG9smJdzFDUFf3Z4JCDEilUxiSX6qFM4eqI0S8RK1UZMTfjueRv_hdUD2GRsqtRN7M2DHnQ_C52PXzFuAPQJvOvFcV_WaK180qa11aiwdnUMas1Ii-JxpAUIOIcdM6RkrgfPAZ5zmio8xAGsy8m9nQwnH0Poss" \
    -d '{
            "payload": {
                "notification": {
                    "category": "IM",
                    "title": "xxxx",
                    "body": "xxxx",
                    "clickAction": {
                        "actionType": 0,
                        "action":"com.app.action"
                    }
                }
            },
            "target": {
                "token": ["MAM1LgQswyQA1wYAstQyDwAAAGQAAAAAAAQSe7IZGR_cllkhr3nsuHejUiUof_f6UBYR-VczGwTB856koCrbZn5PN_SBYN0V39gI9sL7_OXdBoL9"]
            },
            "pushOptions": {
              "testMessage": true,
              "ttl": 86400
            }
    }

    ' \
    "https://push-api.cloud.huawei.com/v3/388421841222065037/messages:send"
}
