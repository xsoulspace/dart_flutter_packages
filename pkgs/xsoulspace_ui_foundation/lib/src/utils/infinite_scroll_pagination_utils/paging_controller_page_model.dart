import 'package:flutter/foundation.dart';
import 'package:from_json_to_json/from_json_to_json.dart';

@immutable
class PagingControllerPageModel<E> {
  const PagingControllerPageModel({
    required this.values,
    required this.currentPage,
    required this.pagesCount,
  });
  factory PagingControllerPageModel.fromJson(
    final Map<String, dynamic> json,
    final E Function(Object? json) fromJsonT,
  ) => _$PagingControllerPageModelFromJson(json, fromJsonT);
  Map<String, dynamic> toJson(final Map<String, dynamic> Function(E) toJsonT) =>
      _$PagingControllerPageModelToJson(this, toJsonT);

  final List<E> values;
  final int pagesCount;
  final int currentPage;

  PagingControllerPageModel<E> copyWith({
    final List<E>? values,
    final int? pagesCount,
    final int? currentPage,
  }) => PagingControllerPageModel<E>(
    values: values ?? this.values,
    pagesCount: pagesCount ?? this.pagesCount,
    currentPage: currentPage ?? this.currentPage,
  );
}

PagingControllerPageModel<E> _$PagingControllerPageModelFromJson<E>(
  final Map<String, dynamic> json,
  final E Function(Object? json) fromJsonE,
) => PagingControllerPageModel<E>(
  values: jsonDecodeListAs<dynamic>(json['values']).map(fromJsonE).toList(),
  currentPage: jsonDecodeInt(json['currentPage']),
  pagesCount: jsonDecodeInt(json['pagesCount']),
);

Map<String, dynamic> _$PagingControllerPageModelToJson<E>(
  final PagingControllerPageModel<E> instance,
  final Object? Function(E value) toJsonE,
) => <String, dynamic>{
  'values': instance.values.map(toJsonE).toList(),
  'pagesCount': instance.pagesCount,
  'currentPage': instance.currentPage,
};

class PagingControllerRequestModel<TData> {
  PagingControllerRequestModel({this.page = 0, this.limit = 10, this.data});
  Map<String, dynamic> toJson(
    final Map<String, dynamic> Function(TData?) toJsonT,
  ) => {'page': page, 'limit': limit, 'data': toJsonT(data)};

  final int page;
  final int limit;
  final TData? data;
}
