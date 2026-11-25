
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/notification_api_service.dart';
import 'home_screen.dart';
import 'route_planner_screen.dart';
import 'live_map_screen.dart';
import 'safe_places_screen.dart';
import 'report_hazard_screen.dart';
import 'community_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const RoutePlannerScreen(),
    const LiveMapScreen(),
    const SafePlacesScreen(),
    const ReportHazardScreen(),
    const CommunityScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF1E293B),
        selectedItemColor: Colors.cyanAccent,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.alt_route),
            activeIcon: Icon(Icons.alt_route),
            label: 'Route',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_hospital_outlined),
            activeIcon: Icon(Icons.local_hospital),
            label: 'Safe',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.warning_amber_rounded),
            activeIcon: Icon(Icons.warning),
            label: 'Report',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.groups_outlined),
            activeIcon: Icon(Icons.groups),
            label: 'Community',
          ),
        ],
      ),
    );
  }
}

class PharosAppBar extends StatefulWidget implements PreferredSizeWidget {
  const PharosAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  State<PharosAppBar> createState() => _PharosAppBarState();
}

class _PharosAppBarState extends State<PharosAppBar> {
  void _showAuthDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => const _AuthDialog(),
    );
  }

  void _showProfileDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF162032),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Pharos Profile',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'You are logged in to your Pharos account.',
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0055FF),
              ),
              onPressed: () async {
                try {
                  await AuthService.logout();

                  if (!mounted || !dialogContext.mounted) return;

                  Navigator.pop(dialogContext);

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('You have been logged out.'),
                    ),
                  );
                } catch (e) {
                  if (!dialogContext.mounted) return;

                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('Logout failed: $e')),
                  );
                }
              },
              child: const Text(
                'Logout',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showNotificationsModal() {
    if (!AuthService.isLoggedIn) {
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF162032),
        builder: (sheetContext) => Padding(
          padding: const EdgeInsets.all(24),
          child: ValueListenableBuilder<bool>(
            valueListenable: AuthService.authState,
            builder: (context, loggedIn, child) {
              if (loggedIn) {
                return const SizedBox(
                  height: 120,
                  child: Center(
                    child: Text(
                      'Please reopen notifications.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.notifications_off_outlined,
                    size: 48,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Login to access your notifications.',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _showAuthDialog();
                    },
                    child: const Text('Login Now'),
                  ),
                ],
              );
            },
          ),
        ),
      );
      return;
    }

    Future<Map<String, dynamic>> notificationsFuture =
        NotificationApiService.getNotifications();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF162032),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> refreshNotifications() async {
              setModalState(() {
                notificationsFuture =
                    NotificationApiService.getNotifications();
              });
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.65,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Notifications',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.refresh,
                              color: Colors.cyanAccent,
                            ),
                            onPressed: refreshNotifications,
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.grey,
                            ),
                            onPressed: () => Navigator.pop(sheetContext),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white12),
                      Expanded(
                        child: FutureBuilder<Map<String, dynamic>>(
                          future: notificationsFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.cyanAccent,
                                ),
                              );
                            }

                            if (snapshot.hasError) {
                              return Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: Colors.redAccent,
                                      size: 40,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      snapshot.error.toString(),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextButton(
                                      onPressed: refreshNotifications,
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final data = snapshot.data!;
                            final items =
                                data['notifications'] as List<dynamic>? ?? [];
                            final unreadCount =
                                data['unread_count'] as int? ?? 0;

                            return Column(
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '$unreadCount unread',
                                      style: const TextStyle(
                                        color: Colors.cyanAccent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (unreadCount > 0)
                                      TextButton(
                                        onPressed: () async {
                                          try {
                                            await NotificationApiService
                                                .markAllAsRead();
                                            await refreshNotifications();
                                          } catch (e) {
                                            if (!sheetContext.mounted) return;
                                            ScaffoldMessenger.of(sheetContext)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Could not update notifications: $e',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        child: const Text('Mark all as read'),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: items.isEmpty
                                      ? const Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.notifications_none,
                                                size: 52,
                                                color: Colors.grey,
                                              ),
                                              SizedBox(height: 12),
                                              Text(
                                                'No notifications yet.',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              SizedBox(height: 6),
                                              Text(
                                                'Safety alerts will appear here.',
                                                style: TextStyle(
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : ListView.separated(
                                          itemCount: items.length,
                                          separatorBuilder: (context, index) =>
                                              const Divider(
                                            color: Colors.white12,
                                            height: 1,
                                          ),
                                          itemBuilder: (context, index) {
                                            final item =
                                                Map<String, dynamic>.from(
                                              items[index] as Map,
                                            );
                                            final isRead =
                                                item['is_read'] == true;
                                            final id = item['id'] as int;
                                            final createdAt =
                                                DateTime.tryParse(
                                              item['created_at']?.toString() ??
                                                  '',
                                            )?.toLocal();

                                            return ListTile(
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 6,
                                              ),
                                              leading: Icon(
                                                item['type'] == 'hazard'
                                                    ? Icons.warning_amber_rounded
                                                    : item['type'] ==
                                                            'risk_escalation'
                                                        ? Icons.trending_up
                                                        : Icons.notifications,
                                                color: isRead
                                                    ? Colors.grey
                                                    : Colors.cyanAccent,
                                              ),
                                              title: Text(
                                                item['title']?.toString() ?? '',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: isRead
                                                      ? FontWeight.normal
                                                      : FontWeight.bold,
                                                ),
                                              ),
                                              subtitle: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    item['body']?.toString() ??
                                                        '',
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                    ),
                                                  ),
                                                  if (createdAt != null) ...[
                                                    const SizedBox(height: 5),
                                                    Text(
                                                      createdAt
                                                          .toString()
                                                          .substring(0, 16),
                                                      style: const TextStyle(
                                                        color: Colors.grey,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              trailing: isRead
                                                  ? const Icon(
                                                      Icons.done,
                                                      color: Colors.grey,
                                                    )
                                                  : IconButton(
                                                      tooltip: 'Mark as read',
                                                      icon: const Icon(
                                                        Icons
                                                            .mark_email_read_outlined,
                                                        color: Colors.cyanAccent,
                                                      ),
                                                      onPressed: () async {
                                                        try {
                                                          await NotificationApiService
                                                              .markAsRead(id);
                                                          await refreshNotifications();
                                                        } catch (e) {
                                                          if (!sheetContext
                                                              .mounted) {
                                                            return;
                                                          }
                                                          ScaffoldMessenger.of(
                                                            sheetContext,
                                                          ).showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                'Could not update notification: $e',
                                                              ),
                                                            ),
                                                          );
                                                        }
                                                      },
                                                    ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.cyan.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.shield,
              color: Colors.cyanAccent,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pharos',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Safer Roads, Brighter Tomorrows.',
                style: TextStyle(color: Colors.grey, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(
            Icons.notifications_outlined,
            color: Colors.white70,
          ),
          onPressed: _showNotificationsModal,
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ValueListenableBuilder<bool>(
            valueListenable: AuthService.authState,
            builder: (context, loggedIn, child) {
              return GestureDetector(
                onTap: loggedIn ? _showProfileDialog : _showAuthDialog,
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: loggedIn
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.cyan.withValues(alpha: 0.3),
                  child: Icon(
                    loggedIn ? Icons.person : Icons.person_outline,
                    color: loggedIn
                        ? Colors.greenAccent
                        : Colors.cyanAccent,
                    size: 20,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AuthDialog extends StatefulWidget {
  const _AuthDialog();

  @override
  State<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<_AuthDialog> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isRegistering = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  String _preferredLanguage = 'en';
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (_isRegistering && name.isEmpty) {
      setState(() => _errorMessage = 'Please enter your name.');
      return;
    }

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = 'Please enter a valid email address.');
      return;
    }

    if (password.length < 8) {
      setState(() => _errorMessage = 'Password must contain at least 8 characters.');
      return;
    }

    if (password.length > 72) {
      setState(() => _errorMessage = 'Password is too long.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      if (_isRegistering) {
        await AuthService.register(
          name: name,
          email: email,
          password: password,
          preferredLanguage: _preferredLanguage,
        );

        if (!mounted) return;

        setState(() {
          _isRegistering = false;
          _passwordController.clear();
          _successMessage =
              'Registration successful! Please log in with your account.';
        });
      } else {
        await AuthService.login(
          email: email,
          password: password,
        );

        if (!mounted) return;

        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey),
      filled: true,
      fillColor: const Color(0xFF0F172A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF162032),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          const Icon(Icons.lock_outline, color: Colors.cyanAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _isRegistering ? 'Create Account' : 'User Login',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isRegistering
                    ? 'Create your Pharos account.'
                    : 'Sign in to access your Pharos account.',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),

              if (_isRegistering) ...[
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: _inputDecoration('Full Name'),
                ),
                const SizedBox(height: 12),
              ],

              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration('Email Address'),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: _inputDecoration('Password').copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),

              if (_isRegistering) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _preferredLanguage,
                  dropdownColor: const Color(0xFF162032),
                  decoration: _inputDecoration('Preferred Language'),
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(
                      value: 'en',
                      child: Text('English'),
                    ),
                    DropdownMenuItem(
                      value: 'hi',
                      child: Text('Hindi'),
                    ),
                    DropdownMenuItem(
                      value: 'kn',
                      child: Text('Kannada'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _preferredLanguage = value);
                    }
                  },
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                  ),
                ),
              ],

              if (_successMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _successMessage!,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading
              ? null
              : () {
                  setState(() {
                    _isRegistering = !_isRegistering;
                    _errorMessage = null;
                    _successMessage = null;
                    _passwordController.clear();
                  });
                },
          child: Text(
            _isRegistering ? 'Already have an account? Login' : 'Register',
            style: const TextStyle(color: Colors.cyanAccent),
          ),
        ),
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Colors.grey),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0055FF),
          ),
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _isRegistering ? 'Register' : 'Login',
                  style: const TextStyle(color: Colors.white),
                ),
        ),
      ],
    );
  }
}


