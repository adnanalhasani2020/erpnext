// ignore_for_file: prefer_interpolation_to_compose_strings, prefer_const_constructors
import 'dart:core';
import 'dart:core' as core;
import 'dart:convert';
import 'dart:io';

import '../models/erp_models.dart';

part 'frappe_api_core.dart';
part 'master_data_api.dart';
part 'inventory_api.dart';
part 'sales_api.dart';
part 'purchases_api.dart';
part 'accounting_api.dart';
part 'payments_api.dart';
part 'bank_reconciliation_api.dart';
part 'reports_api.dart';
part 'hr_api.dart';
part 'payroll_api.dart';

class _DirectHttpOverrides extends HttpOverrides {}

class FrappeApi extends _FrappeApiCore with MasterDataApiMixin, InventoryApiMixin, SalesApiMixin, PurchasesApiMixin, AccountingApiMixin, PaymentsApiMixin, BankReconciliationApiMixin, ReportsApiMixin, HrApiMixin, PayrollApiMixin {
  FrappeApi({super.httpClient});

  static const int pageSize = 100;

  static Uri buildResourcePageUri({
      required String baseUrl,
      required String resource,
      required List<String> fields,
      List<List<dynamic>>? filters,
      List<List<dynamic>>? orFilters,
      required String orderBy,
      int start = 0,
      int pageLength = pageSize,
    }) {
      final parameters = <String, String>{
        'fields': jsonEncode(fields),
        'limit_page_length': (pageLength < 1 ? 1 : pageLength).toString(),
        'limit_start': (start < 0 ? 0 : start).toString(),
        'order_by': orderBy,
      };
      if (filters != null && filters.isNotEmpty) {
        parameters['filters'] = jsonEncode(filters);
      }
      if (orFilters != null && orFilters.isNotEmpty) {
        parameters['or_filters'] = jsonEncode(orFilters);
      }
      final normalizedBase = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final baseUri = Uri.parse(normalizedBase);
      // Build the resource path from decoded segments so names containing spaces
      // are encoded exactly once. Parsing an already-escaped path and then
      // replacing query parameters can otherwise double-escape "%20" as "%2520".
      final pathSegments = <String>[
        ...baseUri.pathSegments.where((segment) => segment.isNotEmpty),
        'api',
        'resource',
        resource,
      ];
      return baseUri.replace(
        pathSegments: pathSegments,
        queryParameters: parameters,
      );
    }

  static const Set<String> salesWorkflowDoctypes = {'Quotation', 'Sales Order', 'Delivery Note', 'Sales Invoice'};

  static const core.Map<String, List<String>> _masterDataFields = {
      'Item': ['name', 'item_code', 'item_name', 'item_group', 'stock_uom',
        'is_stock_item', 'has_serial_no', 'has_batch_no', 'has_expiry_date', 'disabled', 'uoms',
        'image', 'description', 'brand', 'country_of_origin', 'weight_per_unit', 'weight_uom',
        'end_of_life', 'shelf_life_in_days', 'valuation_method', 'standard_rate', 'is_sales_item',
        'is_purchase_item', 'allow_alternative_item', 'has_variants', 'variant_of', 'is_fixed_asset',
        'is_customer_provided_item', 'inspection_required_before_purchase', 'inspection_required_before_delivery',
        'quality_inspection_template', 'default_bom', 'customer_code', 'delivered_by_supplier',
        'serial_no_series', 'batch_number_series', 'use_serial_no_wise_valuation', 'create_new_batch',
        'default_material_request_type', 'lead_time_days', 'safety_stock', 'default_item_manufacturer',
        'default_manufacturer_part_no'],
      'Supplier': ['name', 'supplier_name', 'supplier_type', 'supplier_group',
        'country', 'tax_id', 'mobile_no', 'email_id', 'website', 'disabled'],
      'Customer': ['name', 'customer_name', 'customer_type', 'customer_group', 'territory',
        'tax_id', 'mobile_no', 'email_id', 'website', 'default_currency', 'default_price_list', 'disabled'],
      'Customer Group': ['name', 'customer_group_name', 'parent_customer_group', 'is_group', 'disabled'],
      'Territory': ['name', 'territory_name', 'parent_territory', 'is_group', 'disabled'],
      'Sales Person': ['name', 'sales_person_name', 'parent_sales_person', 'commission_rate', 'is_group', 'enabled', 'employee'],
      'Warehouse': ['name', 'warehouse_name', 'company', 'parent_warehouse', 'is_group', 'disabled'],
      'Item Group': ['name', 'item_group_name', 'parent_item_group', 'is_group', 'disabled'],
      'UOM': ['name', 'uom_name', 'must_be_whole_number', 'enabled'],
      'Supplier Group': ['name', 'supplier_group_name', 'parent_supplier_group', 'is_group', 'disabled'],
      'Price List': ['name', 'price_list_name', 'currency', 'buying', 'selling', 'enabled'],
    };

  static const core.Map<String, Set<String>> _masterDataWritableFields = {
      'Item': {'item_code', 'item_name', 'item_group', 'stock_uom',
        'is_stock_item', 'has_serial_no', 'has_batch_no', 'has_expiry_date', 'disabled', 'uoms',
        'image', 'description', 'brand', 'country_of_origin', 'weight_per_unit', 'weight_uom',
        'end_of_life', 'shelf_life_in_days', 'valuation_method', 'standard_rate', 'is_sales_item',
        'is_purchase_item', 'allow_alternative_item', 'has_variants', 'variant_of', 'is_fixed_asset',
        'is_customer_provided_item', 'inspection_required_before_purchase', 'inspection_required_before_delivery',
        'quality_inspection_template', 'default_bom', 'customer_code', 'delivered_by_supplier',
        'serial_no_series', 'batch_number_series', 'use_serial_no_wise_valuation', 'create_new_batch',
        'default_material_request_type', 'lead_time_days', 'safety_stock', 'default_item_manufacturer',
        'default_manufacturer_part_no', 'barcodes'},
      'Supplier': {'supplier_name', 'supplier_type', 'supplier_group',
        'country', 'tax_id', 'mobile_no', 'email_id', 'website', 'disabled'},
      'Customer': {'customer_name', 'customer_type', 'customer_group', 'territory',
        'tax_id', 'mobile_no', 'email_id', 'website', 'default_currency', 'default_price_list', 'disabled'},
      'Customer Group': {'customer_group_name', 'parent_customer_group', 'is_group', 'disabled'},
      'Territory': {'territory_name', 'parent_territory', 'is_group', 'disabled'},
      'Sales Person': {'sales_person_name', 'parent_sales_person', 'commission_rate', 'is_group', 'enabled', 'employee'},
      'Warehouse': {'warehouse_name', 'company', 'parent_warehouse', 'is_group', 'disabled'},
      'Item Group': {'item_group_name', 'parent_item_group', 'is_group', 'disabled'},
      'UOM': {'uom_name', 'must_be_whole_number', 'enabled'},
      'Supplier Group': {'supplier_group_name', 'parent_supplier_group', 'is_group', 'disabled'},
      'Price List': {'price_list_name', 'currency', 'buying', 'selling', 'enabled'},
    };

  static const core.Map<String, List<String>> _hrFields = {
      'Employee': ['name', 'employee_name', 'company', 'department', 'designation',
        'status', 'date_of_joining', 'reports_to', 'cell_number', 'prefered_email'],
      'Attendance': ['name', 'employee', 'employee_name', 'company', 'attendance_date',
        'status', 'docstatus', 'leave_type'],
      'Leave Application': ['name', 'employee', 'employee_name', 'company', 'leave_type',
        'from_date', 'to_date', 'total_leave_days', 'status', 'docstatus',
        'posting_date', 'description'],
      'Expense Claim': ['name', 'employee', 'employee_name', 'company', 'posting_date',
        'total_claimed_amount', 'total_sanctioned_amount', 'total_amount_reimbursed', 'approval_status',
        'status', 'docstatus'],
      'Salary Slip': ['name', 'employee', 'employee_name', 'company', 'start_date',
        'end_date', 'gross_pay', 'total_deduction', 'net_pay', 'currency', 'status', 'docstatus'],
    };
}

class _ApiResponse {
  const _ApiResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
