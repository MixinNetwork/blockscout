defmodule Explorer.Repo.Migrations.TokensAddAssetIdColumn do
  use Ecto.Migration

  def change do
    alter table("tokens") do
      add :asset_id, :text
    end
  end
end
