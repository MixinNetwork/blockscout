defmodule Explorer.Repo.Migrations.TokensAddMainnetContractColumn do
  use Ecto.Migration

  def change do
    alter table("tokens") do
      add(:ethereum_contract, :bytea)
    end
  end
end
