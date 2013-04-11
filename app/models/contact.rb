# encoding: utf-8
# author: Boris Barroso
# email: boriscyber@gmail.com
class Contact < ActiveRecord::Base

  ########################################
  # Relationships
  has_many :contact_accounts, foreign_key: :contact_id, conditions: {type: 'ContactAccount'}

  has_many :incomes,  foreign_key: :contact_id, conditions: {type: 'Income'}
  has_many :expenses, foreign_key: :contact_id, conditions: {type: 'Expense'}

  has_many :inventory_operations

  ########################################
  # Validations
  validates :matchcode, presence: true, uniqueness: { scope: :type }

  validates_email_format_of :email, allow_blank: true, message: I18n.t('errors.messages.invalid_email_format')

  ########################################
  # Scopes
  scope :clients, where(client: true)
  scope :suppliers, where(supplier: true)
  scope :search, ->(s) { 
    s = "%#{s}%"
    where{(matchcode.like "#{s}") | (first_name.like "#{s}")| (last_name.like "#{s}")}
  }

  default_scope where(staff: false)

  # Serialization
  serialize :incomes_status, JSON
  serialize :expenses_status, JSON

  ########################################
  # Methods

  # Finds a contact using the type
  # @param String
  def self.find_with_type(type)
    type = 'all' unless TYPES.include?(type)
    case type
    when 'Client' then Contact.clients
    when 'Supplier' then Contact.suppliers
    when 'All' then Contact.scoped
    end
  end

  def to_s
    matchcode
  end

  def account_cur(cur)
    accounts.where(currency: cur).first
  end

  def complete_name
    "#{first_name} #{last_name}"
  end
  alias_method :pdf_name, :complete_name

  # Creates an instance of an account with the defined currency
  def set_account_currency(cur)
    self.accounts.build( name: self.to_s, currency: cur, amount: 0)
  end
end
