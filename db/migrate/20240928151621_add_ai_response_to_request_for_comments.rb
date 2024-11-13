class AddAiResponseToRequestForComments < ActiveRecord::Migration[7.1]
  def change
    add_column :request_for_comments, :ai_response, :text
  end
end
