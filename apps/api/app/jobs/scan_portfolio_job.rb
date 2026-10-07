class ScanPortfolioJob < PrivateFileScanJob
  private

  def file_model
    Talent::PortfolioItem
  end
end
