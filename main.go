package main

import "jspp/testgo/cmd"

// @Summary 查询权限菜单
// @Description 查询权限菜单
// @Accept  json
// @Produce  json
//
// @Success 200 {object} BaseResp "ok"
// @Router /api/v1/menu/my/select [get]
func Say() {

}

// @Summary 查询权限菜单
// @Description 查询权限菜单
// @Accept  json
// @Produce  json
//
// @Success 200 {object} BaseResp "ok"
// @Router /api/v1/menu/my/select [get]
func main() {
	cmd.Exec()
}
