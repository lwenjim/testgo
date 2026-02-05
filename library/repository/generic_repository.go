package repository

import (
	"context"
	"strings"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// BaseModel 基础模型接口
type BaseModel interface {
	GetID() uint
	SetID(id uint)
	GetCreatedAt() time.Time
	GetUpdatedAt() time.Time
}

// BaseEntity 基础实体
type BaseEntity struct {
	ID        uint           `gorm:"primarykey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

func (b *BaseEntity) GetID() uint             { return b.ID }
func (b *BaseEntity) SetID(id uint)           { b.ID = id }
func (b *BaseEntity) GetCreatedAt() time.Time { return b.CreatedAt }
func (b *BaseEntity) GetUpdatedAt() time.Time { return b.UpdatedAt }

// Repository 泛型仓库接口
type Repository[T any] interface {
	Create(ctx context.Context, entity *T) error
	CreateBatch(ctx context.Context, entities []*T) error
	Update(ctx context.Context, entity *T) error
	Save(ctx context.Context, entity *T) error
	Delete(ctx context.Context, id uint) error
	SoftDelete(ctx context.Context, id uint) error
	FindByID(ctx context.Context, id uint) (*T, error)
	FindOne(ctx context.Context, query interface{}, args ...interface{}) (*T, error)
	FindAll(ctx context.Context) ([]*T, error)
	Find(ctx context.Context, query interface{}, args ...interface{}) ([]*T, error)
	Exists(ctx context.Context, query interface{}, args ...interface{}) (bool, error)
	Count(ctx context.Context, query interface{}, args ...interface{}) (int64, error)
	Paginate(ctx context.Context, page, pageSize int, query interface{}, args ...interface{}) ([]*T, *PaginateInfo, error)
	WithTx(tx *gorm.DB) Repository[T]
	BeginTx(ctx context.Context) (Repository[T], error)
	DB() *gorm.DB
	FindWithOptions(ctx context.Context, query interface{}, options *Options) ([]*T, error)
}

// PaginateInfo 分页信息
type PaginateInfo struct {
	Page      int   `json:"page"`
	PageSize  int   `json:"page_size"`
	Total     int64 `json:"total"`
	TotalPage int   `json:"total_page"`
	HasPrev   bool  `json:"has_prev"`
	HasNext   bool  `json:"has_next"`
}

// GormRepository GORM 泛型仓库实现
type GormRepository[T any] struct {
	db *gorm.DB
}

// NewGormRepository 创建新的仓库实例
func NewGormRepository[T any](db *gorm.DB) Repository[T] {
	return &GormRepository[T]{db: db}
}

// Create 创建单条记录
func (r *GormRepository[T]) Create(ctx context.Context, entity *T) error {
	return r.db.WithContext(ctx).Create(entity).Error
}

// CreateBatch 批量创建记录
func (r *GormRepository[T]) CreateBatch(ctx context.Context, entities []*T) error {
	if len(entities) == 0 {
		return nil
	}
	return r.db.WithContext(ctx).CreateInBatches(entities, 100).Error
}

// Update 更新记录
func (r *GormRepository[T]) Update(ctx context.Context, entity *T) error {
	return r.db.WithContext(ctx).Save(entity).Error
}

// Save 保存记录（创建或更新）
func (r *GormRepository[T]) Save(ctx context.Context, entity *T) error {
	return r.db.WithContext(ctx).Save(entity).Error
}

// Delete 硬删除记录
func (r *GormRepository[T]) Delete(ctx context.Context, id uint) error {
	var entity T
	return r.db.WithContext(ctx).Delete(&entity, id).Error
}

// SoftDelete 软删除记录
func (r *GormRepository[T]) SoftDelete(ctx context.Context, id uint) error {
	var entity T
	return r.db.WithContext(ctx).Delete(&entity, id).Error
}

// FindByID 根据ID查找记录
func (r *GormRepository[T]) FindByID(ctx context.Context, id uint) (*T, error) {
	var entity T
	err := r.db.WithContext(ctx).First(&entity, id).Error
	if err != nil {
		return nil, err
	}
	return &entity, nil
}

// FindOne 查找单条记录
func (r *GormRepository[T]) FindOne(ctx context.Context, query interface{}, args ...interface{}) (*T, error) {
	var entity T
	db := r.db.WithContext(ctx)

	switch q := query.(type) {
	case string:
		if len(args) > 0 {
			db = db.Where(q, args...)
		} else {
			db = db.Where(q)
		}
	case map[string]interface{}:
		db = db.Where(q)
	default:
		db = db.Where(query, args...)
	}

	err := db.First(&entity).Error
	if err != nil {
		return nil, err
	}
	return &entity, nil
}

// FindAll 查找所有记录
func (r *GormRepository[T]) FindAll(ctx context.Context) ([]*T, error) {
	var entities []*T
	err := r.db.WithContext(ctx).Find(&entities).Error
	if err != nil {
		return nil, err
	}
	return entities, nil
}

// Find 根据条件查找记录
func (r *GormRepository[T]) Find(ctx context.Context, query interface{}, args ...interface{}) ([]*T, error) {
	var entities []*T
	db := r.db.WithContext(ctx)

	switch q := query.(type) {
	case string:
		if len(args) > 0 {
			db = db.Where(q, args...)
		} else {
			db = db.Where(q)
		}
	case map[string]interface{}:
		db = db.Where(q)
	default:
		db = db.Where(query, args...)
	}

	err := db.Find(&entities).Error
	if err != nil {
		return nil, err
	}
	return entities, nil
}

// Exists 判断记录是否存在
func (r *GormRepository[T]) Exists(ctx context.Context, query interface{}, args ...interface{}) (bool, error) {
	var count int64
	db := r.db.WithContext(ctx).Model(new(T))

	switch q := query.(type) {
	case string:
		if len(args) > 0 {
			db = db.Where(q, args...)
		} else {
			db = db.Where(q)
		}
	case map[string]interface{}:
		db = db.Where(q)
	default:
		db = db.Where(query, args...)
	}

	err := db.Count(&count).Error
	if err != nil {
		return false, err
	}
	return count > 0, nil
}

// Count 统计记录数量
func (r *GormRepository[T]) Count(ctx context.Context, query interface{}, args ...interface{}) (int64, error) {
	var count int64
	db := r.db.WithContext(ctx).Model(new(T))

	switch q := query.(type) {
	case string:
		if len(args) > 0 {
			db = db.Where(q, args...)
		} else {
			db = db.Where(q)
		}
	case map[string]interface{}:
		db = db.Where(q)
	default:
		db = db.Where(query, args...)
	}

	err := db.Count(&count).Error
	return count, err
}

// Paginate 分页查询
func (r *GormRepository[T]) Paginate(ctx context.Context, page, pageSize int, query interface{}, args ...interface{}) ([]*T, *PaginateInfo, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = 10
	}

	offset := (page - 1) * pageSize
	var entities []*T
	var total int64

	db := r.db.WithContext(ctx).Model(new(T))

	// 应用查询条件
	if query != nil {
		switch q := query.(type) {
		case string:
			if len(args) > 0 {
				db = db.Where(q, args...)
			} else {
				db = db.Where(q)
			}
		case map[string]interface{}:
			db = db.Where(q)
		default:
			db = db.Where(query, args...)
		}
	}

	// 获取总数
	err := db.Count(&total).Error
	if err != nil {
		return nil, nil, err
	}

	// 分页查询
	err = db.Offset(offset).Limit(pageSize).Find(&entities).Error
	if err != nil {
		return nil, nil, err
	}

	// 计算分页信息
	totalPage := int((total + int64(pageSize) - 1) / int64(pageSize))
	info := &PaginateInfo{
		Page:      page,
		PageSize:  pageSize,
		Total:     total,
		TotalPage: totalPage,
		HasPrev:   page > 1,
		HasNext:   page < totalPage,
	}

	return entities, info, nil
}

// WithTx 使用事务
func (r *GormRepository[T]) WithTx(tx *gorm.DB) Repository[T] {
	return &GormRepository[T]{db: tx}
}

// BeginTx 开始事务
func (r *GormRepository[T]) BeginTx(ctx context.Context) (Repository[T], error) {
	tx := r.db.WithContext(ctx).Begin()
	if tx.Error != nil {
		return nil, tx.Error
	}
	return &GormRepository[T]{db: tx}, nil
}

// DB 获取原始 DB 实例
func (r *GormRepository[T]) DB() *gorm.DB {
	return r.db
}

// Options 查询选项
type Options struct {
	Preloads  []string
	Selects   []string
	Omits     []string
	Order     string
	Limit     int
	Offset    int
	ForUpdate bool
}

// FindWithOptions 带选项查询
func (r *GormRepository[T]) FindWithOptions(ctx context.Context, query interface{}, options *Options) ([]*T, error) {
	var entities []*T
	db := r.db.WithContext(ctx).Model(new(T))

	// 应用查询条件
	if query != nil {
		switch q := query.(type) {
		case string:
			db = db.Where(q)
		case map[string]interface{}:
			db = db.Where(q)
		default:
			db = db.Where(query)
		}
	}

	// 应用选项
	if options != nil {
		// 预加载关联
		for _, preload := range options.Preloads {
			if strings.Contains(preload, ".") {
				db = db.Preload(preload)
			} else {
				db = db.Preload(preload)
			}
		}

		// 选择字段
		if len(options.Selects) > 0 {
			db = db.Select(options.Selects)
		}

		// 排除字段
		if len(options.Omits) > 0 {
			db = db.Omit(options.Omits...)
		}

		// 排序
		if options.Order != "" {
			db = db.Order(options.Order)
		}

		// 分页
		if options.Limit > 0 {
			db = db.Limit(options.Limit)
		}

		if options.Offset > 0 {
			db = db.Offset(options.Offset)
		}

		// 悲观锁
		if options.ForUpdate {
			db = db.Clauses(clause.Locking{Strength: "UPDATE"})
		}
	}

	err := db.Find(&entities).Error
	if err != nil {
		return nil, err
	}

	return entities, nil
}
