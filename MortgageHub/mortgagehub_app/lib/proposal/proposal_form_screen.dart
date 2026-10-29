import 'package:faker/faker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'proposal_check.dart';
import 'proposal_request.dart';
import 'proposal_summary_screen.dart';
import 'random_proposal.dart';
import 'targeted_proposal.dart';

/// The mortgage proposal request: one scrolling form in three sections
/// (the loan, the property, the borrower). Submitting a valid form opens
/// its summary. **Fill random** fills it with a random, valid request; its
/// menu fills one built for a chosen regulatory check verdict.
class ProposalFormScreen extends StatefulWidget {
  const ProposalFormScreen({super.key, this.faker, this.checker});

  /// Where Fill random's data comes from: a seeded one in tests.
  final Faker? faker;

  /// Passed on to the summary, for its regulatory check.
  final ProposalChecker? checker;

  @override
  State<ProposalFormScreen> createState() => _ProposalFormScreenState();
}

class _ProposalFormScreenState extends State<ProposalFormScreen> {
  final _formKey = GlobalKey<FormState>();

  LoanPurpose _purpose = LoanPurpose.purchase;
  LoanProgram _program = LoanProgram.notSure;
  LoanTerm _term = LoanTerm.years30;
  RateType _rateType = RateType.fixed;
  Timeline? _timeline;
  PropertyType? _propertyType;
  Occupancy _occupancy = Occupancy.primary;
  bool _propertyFound = true;
  String? _state;
  CreditScoreRange? _creditScore;
  EmploymentType? _employment;
  bool _hasCoBorrower = false;
  bool _firstTimeBuyer = false;
  bool _militaryService = false;
  bool _consent = false;
  bool _showConsentError = false;

  /// How many times the form was filled: part of the dropdowns' keys, so
  /// a fill rebuilds them with their new values.
  int _fills = 0;

  final _street = TextEditingController();
  final _city = TextEditingController();
  final _zip = TextEditingController();
  final _value = TextEditingController();
  final _downPayment = TextEditingController();
  final _balance = TextEditingController();
  final _cashOut = TextEditingController();
  final _taxes = TextEditingController();
  final _insurance = TextEditingController();
  final _hoa = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _income = TextEditingController();
  final _debts = TextEditingController();
  final _assets = TextEditingController();

  late final _controllers = [
    _street,
    _city,
    _zip,
    _value,
    _downPayment,
    _balance,
    _cashOut,
    _taxes,
    _insurance,
    _hoa,
    _firstName,
    _lastName,
    _email,
    _phone,
    _income,
    _debts,
    _assets,
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  /// A refinance is always of a home the borrower has.
  bool get _hasAddress => !_purpose.isPurchase || _propertyFound;

  int _amount(TextEditingController controller) =>
      int.tryParse(controller.text) ?? 0;

  int? _optionalAmount(TextEditingController controller) =>
      controller.text.isEmpty ? null : int.tryParse(controller.text);

  /// Fills every field with a random, valid request (random_proposal.dart),
  /// or one built to get [target] from the regulatory check
  /// (targeted_proposal.dart).
  void _fillRandom([CheckStatus? target]) {
    final r = target == null
        ? randomProposal(widget.faker)
        : targetedProposal(target, widget.faker);
    String optional(int? amount) => amount?.toString() ?? '';
    setState(() {
      _fills++;
      _purpose = r.purpose;
      _program = r.program;
      _term = r.term;
      _rateType = r.rateType;
      _timeline = r.timeline;
      _propertyType = r.propertyType;
      _occupancy = r.occupancy;
      _propertyFound = r.propertyFound;
      _state = r.state;
      _creditScore = r.creditScore;
      _employment = r.employment;
      _hasCoBorrower = r.hasCoBorrower;
      _firstTimeBuyer = r.firstTimeBuyer;
      _militaryService = r.militaryService;
      _consent = true;
      _showConsentError = false;
      _street.text = r.street;
      _city.text = r.city;
      _zip.text = r.zip;
      _value.text = '${r.propertyValue}';
      _downPayment.text = '${r.downPayment}';
      _balance.text = '${r.currentBalance}';
      _cashOut.text = '${r.cashOut}';
      _taxes.text = optional(r.annualTaxes);
      _insurance.text = optional(r.annualInsurance);
      _hoa.text = optional(r.monthlyHoa);
      _firstName.text = r.firstName;
      _lastName.text = r.lastName;
      _email.text = r.email;
      _phone.text = r.phone;
      _income.text = '${r.annualIncome}';
      _debts.text = '${r.monthlyDebts}';
      _assets.text = optional(r.assets);
    });
    // Clears the errors of an earlier submit: the new values all pass.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _formKey.currentState?.validate(),
    );
  }

  void _submit() {
    final valid = _formKey.currentState!.validate();
    setState(() => _showConsentError = !_consent);
    if (!valid || !_consent) return;
    final request = ProposalRequest(
      purpose: _purpose,
      program: _program,
      term: _term,
      rateType: _rateType,
      timeline: _timeline!,
      propertyType: _propertyType!,
      occupancy: _occupancy,
      propertyFound: _hasAddress,
      street: _hasAddress ? _street.text.trim() : '',
      city: _hasAddress ? _city.text.trim() : '',
      state: _state!,
      zip: _zip.text,
      propertyValue: _amount(_value),
      downPayment: _purpose.isPurchase ? _amount(_downPayment) : 0,
      currentBalance: _purpose.isPurchase ? 0 : _amount(_balance),
      cashOut: _purpose == LoanPurpose.cashOutRefinance ? _amount(_cashOut) : 0,
      annualTaxes: _optionalAmount(_taxes),
      annualInsurance: _optionalAmount(_insurance),
      monthlyHoa: _optionalAmount(_hoa),
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text,
      hasCoBorrower: _hasCoBorrower,
      creditScore: _creditScore!,
      employment: _employment!,
      annualIncome: _amount(_income),
      monthlyDebts: _amount(_debts),
      assets: _optionalAmount(_assets),
      firstTimeBuyer: _firstTimeBuyer,
      militaryService: _militaryService,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ProposalSummaryScreen(request: request, checker: widget.checker),
      ),
    );
  }

  // Validators

  String? _required(String? text) =>
      (text == null || text.trim().isEmpty) ? 'Required' : null;

  String? _positiveAmount(String? text) {
    if (text == null || text.isEmpty) return 'Required';
    return (int.tryParse(text) ?? 0) > 0 ? null : 'Must be more than \$0';
  }

  String? _anyAmount(String? text) =>
      (text == null || text.isEmpty) ? 'Required (enter 0 for none)' : null;

  String? _validateDownPayment(String? text) {
    if (text == null || text.isEmpty) return 'Required (enter 0 for none)';
    if (_amount(_value) > 0 && (int.tryParse(text) ?? 0) >= _amount(_value)) {
      return 'Must be less than the purchase price';
    }
    return null;
  }

  String? _validateBalance(String? text) {
    final error = _positiveAmount(text);
    if (error != null) return error;
    if (_amount(_value) > 0 && _amount(_balance) >= _amount(_value)) {
      return "Must be less than the home's value";
    }
    return null;
  }

  String? _validateCashOut(String? text) {
    final error = _positiveAmount(text);
    if (error != null) return error;
    if (_amount(_value) > 0 &&
        _amount(_balance) + _amount(_cashOut) >= _amount(_value)) {
      return "Balance plus cash out must be less than the home's value";
    }
    return null;
  }

  /// FHA, VA and USDA loans are for homes the borrower will live in, and
  /// VA loans for service members, veterans and eligible spouses.
  String? _validateProgram(LoanProgram? program) {
    final government =
        program == LoanProgram.fha ||
        program == LoanProgram.va ||
        program == LoanProgram.usda;
    if (government && _occupancy != Occupancy.primary) {
      return '${program!.label} loans are only for a primary residence';
    }
    if (program == LoanProgram.va && !_militaryService) {
      return 'VA loans need military service (answer below)';
    }
    return null;
  }

  String? _validateZip(String? text) => RegExp(r'^\d{5}$').hasMatch(text ?? '')
      ? null
      : 'Enter a 5-digit ZIP code';

  String? _validateEmail(String? text) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text?.trim() ?? '')
      ? null
      : 'Enter a valid email address';

  String? _validatePhone(String? text) =>
      RegExp(r'^\d{10}$').hasMatch(text ?? '')
      ? null
      : 'Enter a 10-digit US phone number';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request a proposal'),
        actions: [
          _FillRandomButton(onFill: _fillRandom),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Tell us about the loan you want, the home and yourself. '
                    "It's not an application: we won't check your credit.",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  _loanSection(),
                  _propertySection(),
                  _borrowerSection(),
                  _consentTile(),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.send),
                    label: const Text('Request proposal'),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loanSection() => _Section(
    title: 'The loan',
    children: [
      _dropdown<LoanPurpose>(
        label: 'What do you want to do?',
        tooltip: 'A rate-and-term refinance replaces your mortgage to change its rate or term. A cash-out refinance borrows more than you owe and pays you the difference.',
        value: _purpose,
        values: LoanPurpose.values,
        onChanged: (value) => setState(() => _purpose = value!),
      ),
      if (_purpose.isPurchase) ...[
        _money(_value, 'Purchase price', validator: _positiveAmount),
        _money(_downPayment, 'Down payment', validator: _validateDownPayment),
      ] else ...[
        _money(_value, "Home's estimated value", validator: _positiveAmount),
        _money(
          _balance,
          'Current mortgage balance',
          validator: _validateBalance,
        ),
        if (_purpose == LoanPurpose.cashOutRefinance)
          _money(
            _cashOut,
            'Cash you want to take out',
            validator: _validateCashOut,
            tooltip: "The cash you'd receive at closing, on top of paying off your current mortgage.",
          ),
      ],
      _dropdown<LoanProgram>(
        label: 'Loan program',
        tooltip: 'Conventional loans follow Fannie Mae and Freddie Mac rules. FHA loans are insured by the government and allow lower scores and down payments. VA loans are for service members and veterans, with no down payment. USDA loans are for eligible rural areas and incomes.',
        value: _program,
        values: LoanProgram.values,
        onChanged: (value) => setState(() => _program = value!),
        validator: _validateProgram,
      ),
      _dropdown<LoanTerm>(
        label: 'Loan term',
        value: _term,
        values: LoanTerm.values,
        onChanged: (value) => setState(() => _term = value!),
      ),
      _dropdown<RateType>(
        label: 'Rate type',
        tooltip: 'A fixed rate never changes. An adjustable rate (ARM) is fixed for the first years, often 5, 7 or 10, then changes every 6 months with the market.',
        value: _rateType,
        values: RateType.values,
        onChanged: (value) => setState(() => _rateType = value!),
      ),
      _dropdown<Timeline>(
        label: _purpose.isPurchase
            ? 'When do you plan to close?'
            : 'When do you want to refinance?',
        tooltip: 'Rates are locked for a set time, often 30 to 60 days, so the proposal is priced for when you expect to close.',
        value: _timeline,
        values: Timeline.values,
        onChanged: (value) => setState(() => _timeline = value),
      ),
    ],
  );

  Widget _propertySection() => _Section(
    title: 'The property',
    children: [
      _dropdown<PropertyType>(
        label: 'Property type',
        value: _propertyType,
        values: PropertyType.values,
        onChanged: (value) => setState(() => _propertyType = value),
      ),
      _dropdown<Occupancy>(
        label: 'How will you use it?',
        tooltip: "Where you live most of the year is your primary residence. Second homes and investment properties (rented out) need larger down payments and cost more, and FHA, VA and USDA loans don't finance them.",
        value: _occupancy,
        values: Occupancy.values,
        onChanged: (value) => setState(() => _occupancy = value!),
      ),
      if (_purpose.isPurchase)
        _yesNo(
          "I've found the home",
          _propertyFound,
          (value) => setState(() => _propertyFound = value),
        ),
      if (_hasAddress) ...[
        _text(_street, 'Street address', validator: _required),
        _text(_city, 'City', validator: _required),
      ],
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: _Field(
              child: DropdownButtonFormField<String>(
                key: ValueKey('state#$_fills'),
                initialValue: _state,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'State'),
                items: [
                  for (final entry in usStates.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) => setState(() => _state = value),
                validator: (value) => value == null ? 'Required' : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _text(
              _zip,
              'ZIP code',
              validator: _validateZip,
              keyboardType: TextInputType.number,
              formatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(5),
              ],
            ),
          ),
        ],
      ),
      _money(
        _taxes,
        'Annual property taxes (optional)',
        tooltip: 'The yearly tax on the home, from the listing or your tax bill. Leave it empty and the lender estimates it from the location.',
      ),
      _money(
        _insurance,
        'Annual homeowners insurance (optional)',
        tooltip: 'The yearly premium that insures the home against damage. Lenders require it. Leave it empty to have it estimated.',
      ),
      _money(
        _hoa,
        'Monthly HOA dues (optional)',
        tooltip: 'Fees to a homeowners association, common for condos, townhouses and planned communities. They count toward your monthly payment.',
      ),
    ],
  );

  Widget _borrowerSection() => _Section(
    title: 'About you',
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _text(_firstName, 'First name', validator: _required),
          ),
          const SizedBox(width: 12),
          Expanded(child: _text(_lastName, 'Last name', validator: _required)),
        ],
      ),
      _text(
        _email,
        'Email',
        validator: _validateEmail,
        keyboardType: TextInputType.emailAddress,
      ),
      _text(
        _phone,
        'Phone',
        validator: _validatePhone,
        keyboardType: TextInputType.phone,
        formatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(10),
        ],
      ),
      _yesNo(
        "I'm applying with a co-borrower",
        _hasCoBorrower,
        (value) => setState(() => _hasCoBorrower = value),
        tooltip: 'Someone who borrows with you, such as a spouse or partner, and is equally responsible for the loan. Their income counts too.',
      ),
      _dropdown<CreditScoreRange>(
        label: 'Estimated credit score',
        tooltip: "Your FICO score, as you know it from your bank or card. We don't check your credit for a proposal; the lender pulls the report later, with your permission.",
        value: _creditScore,
        values: CreditScoreRange.values,
        onChanged: (value) => setState(() => _creditScore = value),
      ),
      _dropdown<EmploymentType>(
        label: 'Employment',
        tooltip: 'W-2 means an employer pays you a salary or wages. Self-employed income (your own business, freelancing) is documented with tax returns instead.',
        value: _employment,
        values: EmploymentType.values,
        onChanged: (value) => setState(() => _employment = value),
      ),
      _money(
        _income,
        _hasCoBorrower
            ? 'Annual income before taxes (both of you)'
            : 'Annual income before taxes',
        validator: _positiveAmount,
        tooltip: 'Gross income: before taxes and deductions, from all borrowers. Lenders compare it with your debts and the new payment.',
        helper:
            "Alimony, child support or separate maintenance income need "
            "not be included unless you want it considered.",
      ),
      _money(
        _debts,
        'Monthly debt payments',
        validator: _anyAmount,
        tooltip: 'Your debts plus the new mortgage payment, divided by your income, is your debt-to-income ratio (DTI), one of the main things lenders check.',
        helper: _purpose.isPurchase
            ? 'Minimum payments on cards, car and student loans. Not rent.'
            : 'Minimum payments on cards, car and student loans. Not the '
                  'mortgage being refinanced.',
      ),
      _money(
        _assets,
        'Savings available to close (optional)',
        tooltip: 'Cash, savings and investments you can use for the down payment and closing costs. Some loans also require months of payments left over as reserves.',
      ),
      if (_purpose.isPurchase)
        _yesNo(
          "I'm a first-time homebuyer",
          _firstTimeBuyer,
          (value) => setState(() => _firstTimeBuyer = value),
          tooltip: "You haven't owned a home in the past 3 years. First-time buyers can get lower down payments and some reduced fees.",
        ),
      _yesNo(
        'I served, or am serving, in the US military (or am a surviving spouse)',
        _militaryService,
        (value) => setState(() => _militaryService = value),
        tooltip: 'Service members, veterans and some surviving spouses can get VA loans, with no down payment and no mortgage insurance.',
      ),
    ],
  );

  Widget _consentTile() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          key: const Key('consent'),
          value: _consent,
          onChanged: (value) => setState(() {
            _consent = value ?? false;
            if (_consent) _showConsentError = false;
          }),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'I agree to be contacted by email or phone about this proposal.',
          ),
        ),
        if (_showConsentError)
          Text(
            'Please agree so we can send you the proposal',
            style: TextStyle(color: scheme.error, fontSize: 12),
          ),
      ],
    );
  }

  // Field builders

  Widget _dropdown<T extends Labeled>({
    required String label,
    required T? value,
    required List<T> values,
    required ValueChanged<T?> onChanged,
    FormFieldValidator<T>? validator,
    String? tooltip,
  }) => _Field(
    child: DropdownButtonFormField<T>(
      key: ValueKey('$label#$_fills'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, suffixIcon: _info(tooltip)),
      items: [
        for (final option in values)
          DropdownMenuItem(value: option, child: Text(option.label)),
      ],
      onChanged: onChanged,
      validator: validator ?? (value) => value == null ? 'Required' : null,
    ),
  );

  Widget _text(
    TextEditingController controller,
    String label, {
    FormFieldValidator<String>? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    String? helper,
    String? prefix,
    String? tooltip,
  }) => _Field(
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
        prefixText: prefix,
        suffixIcon: _info(tooltip),
      ),
      keyboardType: keyboardType,
      inputFormatters: formatters,
      validator: validator,
    ),
  );

  /// Whole US dollars.
  Widget _money(
    TextEditingController controller,
    String label, {
    FormFieldValidator<String>? validator,
    String? helper,
    String? tooltip,
  }) => _text(
    controller,
    label,
    validator: validator,
    helper: helper,
    tooltip: tooltip,
    prefix: '\$ ',
    keyboardType: TextInputType.number,
    formatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(9),
    ],
  );

  Widget _yesNo(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    String? tooltip,
  }) => SwitchListTile(
    title: Row(
      children: [
        Flexible(child: Text(label)),
        ?_info(tooltip),
      ],
    ),
    value: value,
    onChanged: onChanged,
    contentPadding: EdgeInsets.zero,
  );
}

/// A split button: **Fill random** fills any random request; the arrow
/// opens a menu to fill one for a verdict (Processable, Requires review,
/// Not processable).
class _FillRandomButton extends StatelessWidget {
  const _FillRandomButton({required this.onFill});

  final void Function([CheckStatus? target]) onFill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: onFill,
            icon: const Icon(Icons.casino_outlined),
            label: const Text('Fill random'),
            style: TextButton.styleFrom(
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(20),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 24,
            child: VerticalDivider(width: 1, color: scheme.outlineVariant),
          ),
          PopupMenuButton<CheckStatus>(
            key: const Key('fillRandomMenu'),
            tooltip: 'Fill random for a verdict',
            icon: Icon(Icons.arrow_drop_down, color: scheme.primary),
            onSelected: onFill,
            itemBuilder: (context) => [
              for (final status in CheckStatus.values)
                PopupMenuItem(
                  value: status,
                  child: ListTile(
                    leading: Icon(
                      statusIcon(status),
                      color: statusColor(context, status),
                    ),
                    title: Text(status.label),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// An info icon that explains a field: on hover, or on tap on touch screens.
Widget? _info(String? message) => message == null
    ? null
    : Tooltip(
        message: message,
        triggerMode: TooltipTriggerMode.tap,
        showDuration: const Duration(seconds: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.info_outline, size: 18),
        ),
      );

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: child);
}
