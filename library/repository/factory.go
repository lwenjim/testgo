package repository

import (

	"gorm.io/gorm"
)

// RepositoryFactory 仓库工厂
type RepositoryFactory struct {
	db *gorm.DB
}

// NewRepositoryFactory 创建仓库工厂
func NewRepositoryFactory(db *gorm.DB) *RepositoryFactory {
	return &RepositoryFactory{db: db}
}

// UserRepository 用户仓库
func (f *RepositoryFactory) UserRepository() Repository[User] {
	return NewGormRepository[User](f.db)
}

// ProductRepository 产品仓库
func (f *RepositoryFactory) ProductRepository() Repository[Product] {
	return NewGormRepository[Product](f.db)
}

// GetRepository 获取泛型仓库
func GetRepository[T any](db *gorm.DB) Repository[T] {
	return NewGormRepository[T](db)
}
