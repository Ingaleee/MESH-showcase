module Platform
  class Record < ActiveRecord::Base
    self.abstract_class = true
  end
end
