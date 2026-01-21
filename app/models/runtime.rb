class Runtime < ApplicationRecord
  has_many :executions, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :instruction_set, presence: true
  validates :adapter_class, presence: true
end
