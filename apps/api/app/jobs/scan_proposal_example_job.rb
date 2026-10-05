class ScanProposalExampleJob < PrivateFileScanJob
  private

  def file_model
    Marketplace::ProposalExample
  end
end
