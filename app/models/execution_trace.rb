class ExecutionTrace < ApplicationRecord
  belongs_to :execution

  validates :step, presence: true
  validates :pc, presence: true
  validates :opcode, presence: true
end
