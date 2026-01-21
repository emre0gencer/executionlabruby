class CreateRuntimesAndExecutions < ActiveRecord::Migration[8.1]
  def change
    create_table :runtimes do |t|
      t.string :name, null: false
      t.string :instruction_set, null: false
      t.string :adapter_class, null: false
      t.json :config

      t.timestamps
    end

    create_table :executions do |t|
      t.references :program, null: false, foreign_key: true
      t.references :runtime, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.json :result
      t.json :metrics
      t.text :error

      t.timestamps
    end

    create_table :execution_traces do |t|
      t.references :execution, null: false, foreign_key: true
      t.integer :step, null: false
      t.integer :pc, null: false
      t.string :opcode, null: false
      t.json :snapshot

      t.timestamps
    end

    add_index :runtimes, :instruction_set
    add_index :executions, :status
    add_index :execution_traces, [ :execution_id, :step ], unique: true
  end
end
