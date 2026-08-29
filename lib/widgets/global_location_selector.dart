import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'searchable_dropdown_dialog.dart';

class GlobalLocationSelector extends StatefulWidget {
  final String? initialCountry;
  final String? initialState;
  final String? initialCity;
  final Function(String country, String state, String city, double? lat, double? lon) onLocationChange;

  const GlobalLocationSelector({
    super.key,
    this.initialCountry,
    this.initialState,
    this.initialCity,
    required this.onLocationChange,
  });

  @override
  State<GlobalLocationSelector> createState() => _GlobalLocationSelectorState();
}

class _GlobalLocationSelectorState extends State<GlobalLocationSelector> {
  String _selectedCountry = '';
  String _selectedState = '';
  String _selectedCity = '';

  List<String> _countries = [];
  List<String> _states = [];
  List<String> _cities = [];

  bool _loadingCountries = false;
  bool _loadingStates = false;
  bool _loadingCities = false;
  bool _loadingCoords = false;

  final String _apiBase = 'https://countriesnow.space/api/v0.1';

  @override
  void initState() {
    super.initState();
    _selectedCountry = widget.initialCountry ?? '';
    _selectedState = widget.initialState ?? '';
    _selectedCity = widget.initialCity ?? '';
    _fetchCountries();
  }

  Future<void> _fetchCountries() async {
    setState(() => _loadingCountries = true);
    try {
      final res = await http.get(Uri.parse('$_apiBase/countries/positions'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final list = (data['data'] as List).map((e) => e['name'].toString()).toList();
        setState(() {
          _countries = list;
        });
        if (_selectedCountry.isNotEmpty) {
          _fetchStates(_selectedCountry);
        }
      }
    } catch (e) {
      debugPrint('Error fetching countries: $e');
    } finally {
      if (mounted) setState(() => _loadingCountries = false);
    }
  }

  Future<void> _fetchStates(String country) async {
    setState(() => _loadingStates = true);
    try {
      final res = await http.get(
        Uri.parse('$_apiBase/countries/states/q?country=${Uri.encodeComponent(country)}'),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final list = (data['data']['states'] as List).map((e) => e['name'].toString()).toList();
        setState(() {
          _states = list;
        });
        if (_selectedState.isNotEmpty) {
          _fetchCities(country, _selectedState);
        }
      } else if (res.statusCode == 404) {
        setState(() => _states = []);
      }
    } catch (e) {
      debugPrint('Error fetching states: $e');
    } finally {
      if (mounted) setState(() => _loadingStates = false);
    }
  }

  Future<void> _fetchCities(String country, String state) async {
    setState(() => _loadingCities = true);
    try {
      final res = await http.get(
        Uri.parse('$_apiBase/countries/state/cities/q?country=${Uri.encodeComponent(country)}&state=${Uri.encodeComponent(state)}'),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final list = (data['data'] as List).map((e) => e.toString()).toList();
        setState(() {
          _cities = list;
        });
      } else if (res.statusCode == 404) {
        setState(() => _cities = []);
      }
    } catch (e) {
      debugPrint('Error fetching cities: $e');
    } finally {
      if (mounted) setState(() => _loadingCities = false);
    }
  }

  Future<void> _fetchCoords(String city) async {
    setState(() => _loadingCoords = true);
    try {
      final res = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/search?format=json&q=$city,$_selectedState,$_selectedCountry&limit=1'),
        headers: {'User-Agent': 'ManavizhaHoroscopeApp/1.0'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as List;
        if (data.isNotEmpty) {
          final lat = double.tryParse(data[0]['lat'].toString());
          final lon = double.tryParse(data[0]['lon'].toString());
          widget.onLocationChange(_selectedCountry, _selectedState, city, lat, lon);
          return;
        }
      }
    } catch (e) {
      debugPrint('Error fetching coords: $e');
    } finally {
      if (mounted) setState(() => _loadingCoords = false);
    }
    // If coords fail, still notify the change without lat/lon
    widget.onLocationChange(_selectedCountry, _selectedState, city, null, null);
  }

  void _notifyChange() {
    widget.onLocationChange(_selectedCountry, _selectedState, _selectedCity, null, null);
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required bool isLoading,
    required bool isDisabled,
    required Function(String) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        readOnly: true,
        controller: TextEditingController(text: value.isEmpty ? 'Select $label' : value),
        style: TextStyle(color: isDisabled ? Colors.grey : Colors.black),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.grey),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          suffixIcon: isLoading 
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) 
              : const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
        ),
        onTap: isDisabled || isLoading ? null : () async {
          final result = await showDialog<String>(
            context: context,
            builder: (ctx) => SearchableDropdownDialog(title: 'Select $label', items: items),
          );
          if (result != null && result != value) {
            onChanged(result);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDropdown(
          label: 'Country',
          value: _selectedCountry,
          items: _countries,
          isLoading: _loadingCountries,
          isDisabled: false,
          onChanged: (val) {
            setState(() {
              _selectedCountry = val;
              _selectedState = '';
              _selectedCity = '';
              _states = [];
              _cities = [];
            });
            _notifyChange();
            _fetchStates(val);
          },
        ),
        _buildDropdown(
          label: 'State / Province',
          value: _selectedState,
          items: _states,
          isLoading: _loadingStates,
          isDisabled: _selectedCountry.isEmpty,
          onChanged: (val) {
            setState(() {
              _selectedState = val;
              _selectedCity = '';
              _cities = [];
            });
            _notifyChange();
            _fetchCities(_selectedCountry, val);
          },
        ),
        _buildDropdown(
          label: 'City',
          value: _selectedCity,
          items: _cities,
          isLoading: _loadingCities || _loadingCoords,
          isDisabled: _selectedState.isEmpty,
          onChanged: (val) {
            setState(() {
              _selectedCity = val;
            });
            _fetchCoords(val);
          },
        ),
      ],
    );
  }
}
