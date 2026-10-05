class ScanWorkFileJob < PrivateFileScanJob
  private

  def file_model
    Engagements::WorkFile
  end
end
