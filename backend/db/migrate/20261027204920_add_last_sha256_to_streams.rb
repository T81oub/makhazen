class AddLastSha256ToStreams < ActiveRecord::Migration[8.1]
  def change
    add_column :streams, :last_sha256, :string
  end
end
