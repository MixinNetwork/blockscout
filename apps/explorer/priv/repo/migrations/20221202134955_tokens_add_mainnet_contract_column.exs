defmodule Explorer.Repo.Migrations.TokensAddEthereumContractAddressHashColumn do
  use Ecto.Migration

  def change do
    alter table("tokens") do
      add(:ethereum_contract_address, :text)
    end
  end
end
