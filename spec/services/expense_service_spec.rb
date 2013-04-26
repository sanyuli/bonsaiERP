# encoding: utf-8
describe ExpenseService do
  let(:details) {
    [{item_id: 1, price: 10.0, quantity: 10, description: "First item"},
     {item_id: 2, price: 20.0, quantity: 20, description: "Second item"}
    ]
  }
  let(:item_ids) { details.map {|v| v[:item_id] } }

  let(:total) { 490 }
  let(:details_total) { details.inject(0) {|s, v| s+= v[:quantity] * v[:price] } }

  let(:valid_params) { {
      date: Date.today, contact_id: 1, total: total,
      currency: 'BOB', bill_number: "E-0001", description: "New expense description",
      expense_details_attributes: details
    }
  }

  before(:each) do
    UserSession.user = build :user, id: 10
    OrganisationSession.organisation = build :organisation, currency: 'BOB'
  end

  context "Initialization" do
    subject { ExpenseService.new_expense(valid_params) }

    it "expense_details" do
      subject.expense.should be_is_a(Expense)
      subject.expense.expense_details.should have(2).items

      subject.expense.expense_details[0].item_id.should eq(details[0][:item_id])
      subject.expense.expense_details[0].description.should eq(details[0][:description])
      subject.expense.expense_details[0].price.should eq(details[0][:price])
      subject.expense.expense_details[0].quantity.should eq(details[0][:quantity])
      subject.expense.expense_details[1].item_id.should eq(details[1][:item_id])
    end

    it "sets_defaults if nil" do
      es = ExpenseService.new_expense
      es.expense.ref_number.should =~ /E-\d{2}-000\d/
      es.expense.currency.should eq('BOB')
      es.expense.date.should eq(Date.today)

      es.expense_details.should have(1).item
    end
  end

  it "#valid?" do
    es = ExpenseService.new_expense(account_to_id: 2, direct_payment: "1")

    es.should_not be_valid
    AccountQuery.any_instance.stub_chain(:bank_cash, where: [( build :cash, id: 2 )])

    es = ExpenseService.new_expense(account_to_id: 2, direct_payment: "1")

    es.should be_valid
  end

  context "Create a expense with default data" do
    before(:each) do
      Expense.any_instance.stub(save: true)
      ExpenseDetail.any_instance.stub(save: true, valid?: true)
    end

    subject { ExpenseService.new_expense(valid_params) }

    it "creates and sets the default states" do
      s = stub
      s.should_receive(:values_of).with(:id, :buy_price).and_return([[1, 10.5], [2, 20.0]])

      Item.should_receive(:where).with(id: item_ids).and_return(s)

      # Create
      subject.create.should be_true

      # Expense
      e = subject.expense
      e.should be_is_a(Expense)
      e.should be_is_draft
      e.should be_active
      e.ref_number.should =~ /E-\d{2}-\d{4}/
      e.date.should be_is_a(Date)

      e.creator_id.should eq(UserSession.id)

      # Number values
      e.exchange_rate.should == 1
      e.total.should == total

      e.gross_total.should == (10 * 10.5 + 20 * 20.0)
      e.balance.should == total
      e.gross_total.should > e.total

      e.discount == e.gross_total - total
      e.should be_discounted

      e.expense_details[0].original_price.should == 10.5
      e.expense_details[0].balance.should == 10.0
      e.expense_details[1].original_price.should == 20.0
      e.expense_details[1].balance.should == 20.0
    end

    it "creates and approves" do
      # Create
      subject.create_and_approve.should be_true

      # Expense
      e = subject.expense
      e.should be_is_a(Expense)
      e.should be_is_approved
      e.should be_active
      e.due_date.should eq(e.date)
      e.approver_id.should eq(UserSession.id)
      e.approver_datetime.should be_is_a(Time)
    end

  end

  context "Update" do
    before(:each) do
      Expense.any_instance.stub(save: true)
      ExpenseDetail.any_instance.stub(save: true)
    end

    subject { ExpenseService.new_expense(valid_params) }

    it "Updates with errors on expense" do
      TransactionHistory.any_instance.should_receive(:create_history).and_return(true)

      e = subject.expense
      e.total = details_total
      e.balance = 0
      e.stub(total_was: e.total)

      e.should be_is_draft
      e.total.should > 200.0

      attributes = valid_params.merge(total: 200)
      # Update
      subject.update(attributes).should be_true

      # Expense
      e = subject.expense

      e.should be_is_paid
      e.should be_has_error
      e.error_messages[:balance].should_not be_blank
    end

    it "update_and_approve" do
      TransactionHistory.any_instance.stub(create_history: true)

      subject.update({}).should be_true
      subject.expense.should be_is_draft

      subject.update_and_approve({})
      subject.expense.should be_is_approved
    end
  end

  describe "create and pay" do
    let(:cash) { build :cash, currency: 'BOB', id: 2 }
    let(:contact) { build :contact, id: 1 }

    before(:each) do
      AccountLedger.any_instance.stub(save_ledger: true)
      Expense.any_instance.stub(contact: contact, id: 100, save: true)
      ExpenseDetail.any_instance.stub(save: true)
    end

    it "creates and pays" do
      AccountQuery.any_instance.stub_chain(:bank_cash, where: [( build :cash, id: 2 )])

      s = stub
      s.should_receive(:values_of).with(:id, :buy_price).and_return([[1, 10], [2, 20.0]])

      Item.should_receive(:where).with(id: item_ids).and_return(s)

      es = ExpenseService.new_expense(valid_params.merge(direct_payment: "1", account_to_id: "2"))
      es.create_and_approve.should be_true

      es.ledger.should be_is_a(AccountLedger)
      # ledger
      es.ledger.account_id.should eq(100)
      es.ledger.account_to_id.should eq(2)
      es.ledger.should be_is_payout
      es.ledger.amount.should == -490.0

      # expense
      es.expense.total.should == 490.0
      es.expense.balance.should == 0.0
      es.expense.discount.should == 10.0
      es.expense.should be_is_paid
    end

    it "updates and pays" do
      AccountQuery.any_instance.stub_chain(:bank_cash, where: [( build :cash, id: 2 )])

      exp = build(:expense, id: 2, state: 'draft', total: 490, balance: 490,
                 ref_number: 'E-13-0007')
      Expense.stub(find: exp)
      exp.stub(total_was: 490)

      s = Object.new
      s.stub(:values_of).with(:id, :buy_price).and_return([[1, 10], [2, 20.0]])

      Item.should_receive(:where).with(id: item_ids).and_return(s)

      es = ExpenseService.find(1)
      es.expense.should eq(exp)

      es.ref_number.should eq('E-13-0007')
      es.total.should == 490.0

      attrs = valid_params.merge(direct_payment: "1", account_to_id: "2")

      es.update_and_approve(attrs).should be_true

      es.ledger.should be_is_a(AccountLedger)
      # ledger
      es.ledger.account_id.should eq(100)
      es.ledger.account_to_id.should eq(2)
      es.ledger.should be_is_payout
      es.ledger.amount.should == -es.expense.total

      # expense
      es.expense.should be_is_paid
      es.expense.total.should == 490.0
      es.expense.balance.should == 0.0
      es.expense.should be_discounted
      es.expense.discount.should == 10.0
    end

    it "sets errors from expense or ledger" do
      es = ExpenseService.new_expense

      es.expense.stub(save: false)
      es.expense.errors[:contact_id] << "Wrong"

      es.create_and_approve.should be_false
      es.errors[:contact_id].should eq(["Wrong"])

      # Errors on both expense and ledger
      es = ExpenseService.new_expense(direct_payment: true)
      es.stub(account_to: build(:cash, id: 3) )

      es.expense.stub(save: false)
      es.expense.errors[:contact_id] << "Wrong"
      es.stub(ledger: build(:account_ledger))
      es.ledger.errors[:reference] << "Blank reference"

      es.create_and_approve.should be_false

      es.errors[:contact_id].should eq(["Wrong"])
      es.errors[:reference].should eq(["Blank reference"])
    end
  end
end
