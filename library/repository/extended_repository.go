package repository

import (
	"context"
	"fmt"
	"reflect"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// ExtendedRepository 扩展的泛型仓库
type ExtendedRepository[T any] struct {
	GormRepository[T]
}

// NewExtendedRepository 创建扩展仓库
func NewExtendedRepository[T any](db *gorm.DB) *ExtendedRepository[T] {
	return &ExtendedRepository[T]{
		GormRepository: GormRepository[T]{db: db},
	}
}

// Upsert 更新或插入（根据主键或唯一索引）
func (r *ExtendedRepository[T]) Upsert(ctx context.Context, entity *T, conflictColumns []string, updateColumns []string) error {
	if len(conflictColumns) == 0 {
		return r.db.WithContext(ctx).Save(entity).Error
	}

	clause2 := clause.OnConflict{
		Columns:   make([]clause.Column, len(conflictColumns)),
		DoUpdates: clause.AssignmentColumns(updateColumns),
	}

	for i, col := range conflictColumns {
		clause2.Columns[i] = clause.Column{Name: col}
	}

	return r.db.WithContext(ctx).Clauses(clause2).Create(entity).Error
}

// UpdateFields 更新指定字段
func (r *ExtendedRepository[T]) UpdateFields(ctx context.Context, id uint, fields map[string]interface{}) error {
	return r.db.WithContext(ctx).Model(new(T)).Where("id = ?", id).Updates(fields).Error
}

// Increment 字段自增
func (r *ExtendedRepository[T]) Increment(ctx context.Context, id uint, field string, value int) error {
	return r.db.WithContext(ctx).Model(new(T)).
		Where("id = ?", id).
		Update(field, gorm.Expr(fmt.Sprintf("%s + ?", field), value)).
		Error
}

// Decrement 字段自减
func (r *ExtendedRepository[T]) Decrement(ctx context.Context, id uint, field string, value int) error {
	return r.db.WithContext(ctx).Model(new(T)).
		Where("id = ?", id).
		Update(field, gorm.Expr(fmt.Sprintf("%s - ?", field), value)).
		Error
}

// BulkUpdate 批量更新
func (r *ExtendedRepository[T]) BulkUpdate(ctx context.Context, ids []uint, updates map[string]interface{}) error {
	return r.db.WithContext(ctx).Model(new(T)).
		Where("id IN ?", ids).
		Updates(updates).
		Error
}

// GetFieldValue 获取字段值
func (r *ExtendedRepository[T]) GetFieldValue(ctx context.Context, id uint, field string) (interface{}, error) {
	var result map[string]interface{}
	err := r.db.WithContext(ctx).Model(new(T)).
		Select(field).
		Where("id = ?", id).
		Take(&result).
		Error

	if err != nil {
		return nil, err
	}

	return result[field], nil
}

// GetColumnNames 获取表字段名
func (r *ExtendedRepository[T]) GetColumnNames() ([]string, error) {
	var model T
	stmt := &gorm.Statement{DB: r.db}
	err := stmt.Parse(&model)
	if err != nil {
		return nil, err
	}

	var columns []string
	for _, field := range stmt.Schema.Fields {
		columns = append(columns, field.DBName)
	}

	return columns, nil
}

// CopyTo 复制记录到新实例
func (r *ExtendedRepository[T]) CopyTo(ctx context.Context, id uint, newEntity *T, excludeFields []string) error {
	// 获取原记录
	original, err := r.FindByID(ctx, id)
	if err != nil {
		return err
	}

	// 使用反射复制字段
	srcValue := reflect.ValueOf(original).Elem()
	dstValue := reflect.ValueOf(newEntity).Elem()

	excludeMap := make(map[string]bool)
	for _, field := range excludeFields {
		excludeMap[field] = true
	}

	for i := 0; i < srcValue.NumField(); i++ {
		fieldType := srcValue.Type().Field(i)
		fieldName := fieldType.Name

		// 跳过排除字段
		if excludeMap[fieldName] {
			continue
		}

		// 跳过不可导出的字段
		if !fieldType.IsExported() {
			continue
		}

		// 复制值
		srcField := srcValue.Field(i)
		dstField := dstValue.FieldByName(fieldName)

		if dstField.IsValid() && dstField.CanSet() {
			dstField.Set(srcField)
		}
	}

	// 创建新记录
	return r.Create(ctx, newEntity)
}
