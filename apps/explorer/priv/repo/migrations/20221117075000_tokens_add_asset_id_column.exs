defmodule Explorer.Repo.Migrations.TokensAddAssetIdColumn do
  use Ecto.Migration

  def change do
    alter table("tokens") do
      add(:mixin_asset_id, :text)
    end
  end
end
