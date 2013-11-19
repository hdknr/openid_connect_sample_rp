class AddJwkSetToProvider < ActiveRecord::Migration
  def change
    add_column :providers, :jwkset, :text
  end
end
