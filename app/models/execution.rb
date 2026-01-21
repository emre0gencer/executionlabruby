class Execution < ApplicationRecord
  belongs_to :program
  belongs_to :runtime
  has_many :execution_traces, dependent: :destroy

  enum :status, {
    pending: "pending",
    running: "running",
    completed: "completed",
    failed: "failed"
  }, default: "pending"

  validates :status, presence: true
end
