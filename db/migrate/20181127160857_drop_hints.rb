class DropHints < ActiveRecord::Migration[5.2]
  def change
    drop_table :hints
  end
end
